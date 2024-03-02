const { ethers, network, upgrades } = require("hardhat")
const { expect } = require("chai")
const { toEther, fromEther } = require("./helper")

// The steps for acquiring eETH on BNB
// 1. Vapor team prepares eETH by depositing ETH into the vault and performing stake to Ether.fi's LiquidityPool contract
// 2. Vapor team sends eETH from ETH to BNB via the elastic cross-chain bridge
// 3. Vapor team lists bridged eETH on the exchange and sets the payment rate between eETH <-> WETH at 1:1
// 4. Users can now buy eETH on BNB with WETH on the exchange and all payments will be redirected to the vault
// 5. Vapor team monitors rebase events from Etherfi's liquidity pool contract and performs a rebase internally for bridge assets
// 6. Users withdraw by requesting a withdrawal and receive the NFT. Vapor Team monitors requests and approves them one by one
// 7. Once approved, users use bridged eETH and NFT together to obtain WETH


const EETH_PROXY = "0x35fa164735182de50811e8e2e824cfb9b6118ac2"

const LIQUIDITY_POOL_PROXY = "0x308861a430be4cce5502d0a12724771fc6daf216"

describe("#eETH", () => {
    
    let forwarder // only deploy on chain A
    let exchange // only deploy on chain B

    let controllerA
    let controllerB

    let vaultA
    let vaultB

    let etherfi_lp
    let etherfi_eeth

    let vapor_eeth

    let mockWETH // WETH on BNB

    let operator
    let bob
    let charlie
    let dave

    before(async () => {
        
        [operator, bob, charlie, dave] = await ethers.getSigners()
        
        // create etherfi's contract instances on forked mainnet
        let eethAddress = await upgrades.erc1967.getImplementationAddress(EETH_PROXY)
        let eethV1 = await ethers.getContractAt("IeETH", eethAddress)
        etherfi_eeth = await eethV1.attach(EETH_PROXY);

        let lpAddress = await upgrades.erc1967.getImplementationAddress(LIQUIDITY_POOL_PROXY);
        let lpV1 = await ethers.getContractAt("ILiquidityPool", lpAddress)
        etherfi_lp = await lpV1.attach(LIQUIDITY_POOL_PROXY)

        // deploy system contracts
        const MultiSigController = await ethers.getContractFactory("MultiSigController")
        const Vault = await ethers.getContractFactory("Vault")
        const TokenFactory = await ethers.getContractFactory("TokenFactory")
        const Forwarder = await ethers.getContractFactory("Forwarder")
        const Exchange = await ethers.getContractFactory("Exchange")
        const MockERC20 = await ethers.getContractFactory("MockERC20")

        // use 2 signatures for sensitive operations
        controllerA = await  MultiSigController.deploy([operator.address, bob.address, charlie.address, dave.address], 2)
        controllerB = await  MultiSigController.deploy([operator.address, bob.address, charlie.address, dave.address], 2)

        vaultA = await Vault.deploy(1, controllerA.target)
        vaultB = await Vault.deploy(2, controllerB.target)

        await controllerA.addContract(vaultA.target)
        await controllerB.addContract(vaultB.target)

        // setup bridged eETH tokens on secondary chain
        const factory = await TokenFactory.deploy()

        await vaultB.setTokenFactory(factory.target);
        await vaultB.createToken("Bridged Etherfi ETH", "EETH", 18)
        vapor_eeth = await ethers.getContractAt("IElasticToken", await vaultB.bridgeTokens(0));

        // register ether.fi's contract address to forwarder
        forwarder = await Forwarder.deploy(controllerA.target, vaultA.target)
        await controllerA.addContract(forwarder.target)
        await forwarder.register(1, etherfi_lp.target)

        // setup exchange 
        exchange = await Exchange.deploy(controllerB.target, vaultB.target)
        await controllerB.addContract(exchange.target)

        // setup Mock WETH on secondary chain
        mockWETH = await MockERC20.deploy("Mock Wrapped Ethereum", "WETH", 18)
    })

    it("should team prepare eETH on the primary chain success", async function () {
        
        // deposit 1.1 ETH into the vault
        await vaultA.connect(operator).depositWithETH({ value: toEther(1.1) })

        // request stake
        await forwarder.requestStake(1, "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE" , toEther(1.1))

        // signing
        await controllerA.connect(operator).confirmRequest(0)
        await controllerA.connect(bob).confirmRequest(0)
        await controllerA.connect(charlie).executeRequest(0)

        // confirming we have ~1.1 eETH in the vault
        expect( fromEther(await etherfi_eeth.balanceOf( vaultA.target )) ).to.be.closeTo(1.1, 0.1)

    })

    it("should team bridge eETH from primary chain to secondary chain success", async function () {

        // constructing cross-chain payload
        const payload = {
            sendingAssetId: etherfi_eeth.target,
            receivingAssetId: vapor_eeth.target,
            sendingChainId: 1,
            receivingChainId: 2,
            callData: await vaultA.getCalldataMint( vaultB.target, toEther(1)),
            transactionType: 0 // minting op on chain B
        }

        // sending 1 eETH to secondary chain
        await vaultA.connect(operator).prepare(payload, toEther(1))
        await vaultB.connect(operator).prepare(payload, toEther(1))

        // signing on both chain
        await controllerA.connect(operator).confirmRequest(1)
        await controllerA.connect(bob).confirmRequest(1)
        await controllerA.connect(charlie).executeRequest(1)

        await controllerB.connect(operator).confirmRequest(0)
        await controllerB.connect(bob).confirmRequest(0)
        await controllerB.connect(charlie).executeRequest(0)

        // confirming we have 1 eETH on the secondary chain's vault
        expect( await vapor_eeth.balanceOf( vaultB.target )).to.equal( toEther(1) )
    })

    it("should team list eETH for sale success", async function () {
        
        // deposit 1 eETH to exchange contract
        await vaultB.connect(operator).requestWithdraw(
            vapor_eeth.target,
            toEther(1),
            exchange.target
        )

        // signing
        await controllerB.connect(operator).confirmRequest(1)
        await controllerB.connect(bob).confirmRequest(1)
        await controllerB.connect(charlie).executeRequest(1)
        
        // setup exchange rate between eETH <-> WETH at 1:1 
        await exchange.connect(operator).setupNewOrder(vapor_eeth.target, toEther(1), [mockWETH.target], [toEther(1)])

        expect( await vapor_eeth.balanceOf( exchange.target )).to.equal( toEther(1) )
    })

    it("should users buy eETH tokens on secondary chain success", async function () {
        
        // mint 0.1 WETH
        await mockWETH.mintTo(bob.address, toEther(0.1))
        await mockWETH.mintTo(dave.address, toEther(0.1))

        // approve
        await mockWETH.connect(bob).approve(exchange.target, ethers.MaxUint256)
        await mockWETH.connect(dave).approve(exchange.target, ethers.MaxUint256)

        // buy eETH with WETH
        await exchange.connect(bob).buy(vapor_eeth.target, toEther(0.1), mockWETH.target, toEther(0.1))
        await exchange.connect(dave).buy(vapor_eeth.target, toEther(0.1), mockWETH.target, toEther(0.1))

        // checking
        expect(await vapor_eeth.balanceOf(bob.address)).to.equal(toEther(0.1))
        expect(await vapor_eeth.balanceOf(dave.address)).to.equal(toEther(0.1))
        expect(await mockWETH.balanceOf( vaultB.target )).to.equal(toEther(0.2))

    })

    it("should users withdraw success", async function () {
        
        // won't rebase for the test
        
        await exchange.connect(bob).requestWithdraw(vapor_eeth.target, toEther(0.1), mockWETH.target, toEther(0.1))

        // checking NFT metadata
        const nftAddresss = await exchange.withdrawNft()
        const nft = await ethers.getContractAt("MockERC721", nftAddresss);
    
        const uri = await nft.tokenURI(1)
        expect(uri.includes(`VaporFund Withdraw NFT #1`)).to.true

        // approving
        await exchange.connect(operator).approveRequestWithdraw([1])
        
        // preparing WETH for withdraw
        await mockWETH.mintTo(exchange.target, toEther(0.1))

        // withdrawing
        await vapor_eeth.connect(bob).approve(exchange.target, ethers.MaxUint256)
        await nft.connect(bob).approve(exchange.target, 1)

        await exchange.connect(bob).withdraw(1)

        // verifying
        expect(await mockWETH.balanceOf(bob.address)).to.equal(toEther(0.1))
    })  

})