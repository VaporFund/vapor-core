const { ethers } = require("hardhat")
const { expect } = require("chai")
const { toEther, fromEther } = require("./helper")

describe("#vaultBridge", () => {

    let controllerA
    let controllerB

    let vaultA
    let vaultB

    let nonRebaseTokenA
    let rebaseTokenA
    let nonRebaseTokenB
    let rebaseTokenB

    let alice
    let bob
    let charlie
    let dave

    before(async () => {
        
        [alice, bob, charlie, dave] = await ethers.getSigners()

        const MultiSigController = await ethers.getContractFactory("MultiSigController")
        const Vault = await ethers.getContractFactory("Vault")
        const MockERC20 = await ethers.getContractFactory("MockERC20")
        const MockRToken = await ethers.getContractFactory("MockRToken")
        const TokenFactory = await ethers.getContractFactory("TokenFactory")

        // deploy all contracts on chain#A
        controllerA = await  MultiSigController.deploy([alice.address, bob.address, charlie.address, dave.address], 2)
        vaultA = await Vault.deploy(1, controllerA.target)
        nonRebaseTokenA = await MockERC20.deploy("Non-Rebase Token", "NON-REBASE", 18)
        rebaseTokenA = await MockRToken.deploy()

        // deploy all contracts on chain#B
        controllerB = await  MultiSigController.deploy([alice.address, bob.address, charlie.address, dave.address], 2)
        vaultB = await Vault.deploy(2, controllerB.target)

        const factory = await TokenFactory.deploy()

        await vaultB.setTokenFactory(factory.target);

        await vaultB.createToken("Non-Rebase Token B", "NON-REBASE-B", 18)
        await vaultB.createToken("Rebase Token B", "REBASE-B", 18)
    })

    it("should fetch all bridge ERC-20 metadata success", async function () {
        
       nonRebaseTokenB = await ethers.getContractAt("IElasticToken", await vaultB.bridgeTokens(0));
       rebaseTokenB = await ethers.getContractAt("IElasticToken", await vaultB.bridgeTokens(1));

       expect( await nonRebaseTokenB.name() ).to.equal("Non-Rebase Token B")
       expect( await nonRebaseTokenB.symbol() ).to.equal("NON-REBASE-B")

       expect( await rebaseTokenB.name() ).to.equal("Rebase Token B")
       expect( await rebaseTokenB.symbol() ).to.equal("REBASE-B")
    
    })

    it("should send tokens from chain A to chain B success", async function () {
        
        // add supported contract
        await controllerA.addContract(vaultA.target)
        await controllerB.addContract(vaultB.target)

        // locking 1 Mil. / 100 tokens of each type to the vault
        await nonRebaseTokenA.mint(toEther(1000000))
        await rebaseTokenA.mint({ value : toEther(100)})

        await nonRebaseTokenA.approve(vaultA.target, ethers.MaxUint256)
        await rebaseTokenA.approve(vaultA.target, ethers.MaxUint256)

        await vaultA.connect(alice).depositWithERC20(nonRebaseTokenA.target, toEther(1000000))
        await vaultA.connect(alice).depositWithERC20(rebaseTokenA.target, toEther(100))

        // writing down the transaction

        const transactionDataNonRebase = {
            sendingAssetId: nonRebaseTokenA.target,
            receivingAssetId: nonRebaseTokenB.target,
            sendingChainId: 1,
            receivingChainId: 2,
            callData: await vaultA.getCalldataMint( vaultB.target, toEther(1000000)),
            transactionType: 0
        }

        const transactionDataRebase = {
            sendingAssetId: rebaseTokenA.target,
            receivingAssetId: rebaseTokenB.target,
            sendingChainId: 1,
            receivingChainId: 2,
            callData: await vaultA.getCalldataMint( vaultB.target, toEther(100)),
            transactionType: 0
        }

        // sending 1 Mil. non-rebase tokens to chain#B
        await vaultA.connect(alice).prepare(transactionDataNonRebase, toEther(1000000))
        await vaultB.connect(alice).prepare(transactionDataNonRebase, toEther(1000000))
        
        await controllerA.connect(alice).confirmRequest(0)
        await controllerA.connect(bob).confirmRequest(0)
        await controllerA.connect(charlie).executeRequest(0)

        await controllerB.connect(alice).confirmRequest(0)
        await controllerB.connect(bob).confirmRequest(0)
        await controllerB.connect(charlie).executeRequest(0)

        // having 1 mil. tokens locked in Chain A's vault
        expect( await nonRebaseTokenA.balanceOf( vaultA.target ) ).to.equal( toEther(1000000) )
        // having 1 mil. bridge tokens locked in Chain B's vault
        expect( await nonRebaseTokenB.balanceOf( vaultB.target ) ).to.equal( toEther(1000000) )

        // sending 100 rebase tokens to chain#B
        await vaultA.connect(alice).prepare(transactionDataRebase, toEther(100))
        await vaultB.connect(alice).prepare(transactionDataRebase, toEther(100))

        await controllerA.connect(alice).confirmRequest(1)
        await controllerA.connect(bob).confirmRequest(1)
        await controllerA.connect(charlie).executeRequest(1)

        await controllerB.connect(alice).confirmRequest(1)
        await controllerB.connect(bob).confirmRequest(1)
        await controllerB.connect(charlie).executeRequest(1)

        // having 100 tokens locked in Chain A's vault
        expect( await rebaseTokenA.balanceOf( vaultA.target ) ).to.equal( toEther(100) )
        // having 100 bridge tokens locked in Chain B's vault
        expect( await rebaseTokenB.balanceOf( vaultB.target ) ).to.equal( toEther(100) )

        expect( await vaultA.totalValueOutOfChain( rebaseTokenA.target ) ).to.equal( toEther( 100))
        expect( await vaultA.totalValueOutOfChain( nonRebaseTokenA.target ) ).to.equal( toEther( 1000000))
    })

    it("should perform rebase on both chains success", async function () {
        
        // add 3% of supply
        await rebaseTokenA.rebase( toEther(3) )

        const transactionDataRebase = {
            sendingAssetId: rebaseTokenA.target,
            receivingAssetId: rebaseTokenB.target,
            sendingChainId: 1,
            receivingChainId: 2,
            callData: await vaultA.getCalldataRebase(toEther(3)),
            transactionType: 1
        }

        // performing rebase on chain B
        await vaultA.connect(alice).prepare(transactionDataRebase, toEther(3))
        await vaultB.connect(alice).prepare(transactionDataRebase, toEther(3))

        await controllerA.connect(alice).confirmRequest(2)
        await controllerA.connect(bob).confirmRequest(2)
        await controllerA.connect(charlie).executeRequest(2)

        await controllerB.connect(alice).confirmRequest(2)
        await controllerB.connect(bob).confirmRequest(2)
        await controllerB.connect(charlie).executeRequest(2)

        // checking 
        expect( await rebaseTokenA.balanceOf( vaultA.target ) ).to.equal( toEther(103) )
        expect( await rebaseTokenA.balanceOf( vaultA.target ) ).to.equal( await rebaseTokenB.balanceOf( vaultB.target ) )
        
        expect( await vaultA.totalValueOutOfChain( rebaseTokenA.target ) ).to.equal( toEther( 103))
    })

    it("should burn tokens on both chains success", async function () {
        
        // burn 10% of supply
        await nonRebaseTokenA.burn( vaultA.target, toEther(100000))

        const transactionDataRebase = {
            sendingAssetId: nonRebaseTokenA.target,
            receivingAssetId: nonRebaseTokenB.target,
            sendingChainId: 1,
            receivingChainId: 2,
            callData: await vaultA.getCalldataBurn( vaultB.target, toEther(100000)),
            transactionType: 2
        }

        // burning
        await vaultA.connect(alice).prepare(transactionDataRebase, toEther(100000))
        await vaultB.connect(alice).prepare(transactionDataRebase, toEther(100000))

        await controllerA.connect(alice).confirmRequest(3)
        await controllerA.connect(bob).confirmRequest(3)
        await controllerA.connect(charlie).executeRequest(3)

        await controllerB.connect(alice).confirmRequest(3)
        await controllerB.connect(bob).confirmRequest(3)
        await controllerB.connect(charlie).executeRequest(3)

        // checking 
        expect( await nonRebaseTokenA.balanceOf( vaultA.target ) ).to.equal( toEther(900000) )
        expect( await nonRebaseTokenA.balanceOf( vaultA.target ) ).to.equal( await nonRebaseTokenB.balanceOf( vaultB.target ) )

        expect( await vaultA.totalValueOutOfChain( nonRebaseTokenA.target ) ).to.equal( toEther( 900000))

    })
    

})