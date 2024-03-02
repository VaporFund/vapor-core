const { ethers } = require("hardhat")
const { expect } = require("chai")
const { toEther, fromEther } = require("./helper")

describe("#exchange", () => {

    let controller
    let vault
    let exchange

    let mockWETH // WETH on BNB
    let rebaseToken // eETH on BNB

    let operator
    let bob
    let charlie
    let dave

    before(async () => {

        [operator, bob, charlie, dave] = await ethers.getSigners()

        const MultiSigController = await ethers.getContractFactory("MultiSigController")
        const Vault = await ethers.getContractFactory("Vault")
        const MockERC20 = await ethers.getContractFactory("MockERC20")
        const MockRToken = await ethers.getContractFactory("MockRToken")
        const Exchange = await ethers.getContractFactory("Exchange")

        controller = await MultiSigController.deploy([operator.address, bob.address, charlie.address, dave.address], 2)
        vault = await Vault.deploy(1, controller.target)

        exchange = await Exchange.deploy(controller.target, vault.target)

        // deploy ERC-20 tokens
        mockWETH = await MockERC20.deploy("Mock Wrapped Ethereum", "WETH", 18)
        rebaseToken = await MockRToken.deploy()
    })

    it("should admin list tokens for sale success", async function () {

        // add supported contract
        await controller.connect(operator).addContract(exchange.target)

        // mint 100 eETH
        await rebaseToken.connect(operator).mint({ value: toEther(100) })

        // deposit 100 eETH to exchange contract
        await rebaseToken.connect(operator).transfer(exchange.target, toEther(100))

        // setup an order for eETH 
        await exchange.connect(operator).setupNewOrder(rebaseToken.target, toEther(100), [mockWETH.target], [toEther(1)])

        // checking
        expect((await exchange.orders(rebaseToken.target)).active).to.true
        expect((await exchange.orders(rebaseToken.target)).enabled).to.true
        expect((await exchange.orders(rebaseToken.target)).beneficialAddress).to.equal(vault.target)
        expect((await exchange.orders(rebaseToken.target)).baseAmount).to.equal(toEther(100))
    })


    it("should user buy eETH tokens success", async function () {

        // mint 0.5 WETH as payment
        await mockWETH.mintTo(bob.address, toEther(0.5))

        // approve
        await mockWETH.connect(bob).approve(exchange.target, ethers.MaxUint256)

        // buy at 1:1 
        await exchange.connect(bob).buy(rebaseToken.target, toEther(0.5), mockWETH.target, toEther(0.5))

        // checking
        expect(await rebaseToken.balanceOf(bob.address)).to.equal(toEther(0.5))

    })


    it("should users buy eETH tokens at a discount success", async function () {

        // now updating to the price to be 0.8 eETH/WETH
        await exchange.connect(operator).updateOrderPrices(rebaseToken.target, [mockWETH.target], [toEther(0.8)]);

        // mint 0.4 WETH 
        await mockWETH.mintTo(charlie.address, toEther(0.4))

        // approve
        await mockWETH.connect(charlie).approve(exchange.target, ethers.MaxUint256)

        // buy at 0.8 eETH/WETH
        await exchange.connect(charlie).buy(rebaseToken.target, toEther(0.5), mockWETH.target, toEther(0.4))

        // checking
        expect(await rebaseToken.balanceOf(charlie.address)).to.equal(toEther(0.5))
    })

    it("should users withdraw success", async function () {

        // rebase by 10% before withdrawal
        await rebaseToken.connect(operator).rebase(toEther(10))

        expect(await rebaseToken.balanceOf(bob.address)).to.equal(toEther(0.55))
        expect(await rebaseToken.balanceOf(charlie.address)).to.equal(toEther(0.55))

        // request withdrawal for both bob and charlie
        await exchange.connect(bob).requestWithdraw(rebaseToken.target, toEther(0.55), mockWETH.target, toEther(0.55))
        await exchange.connect(charlie).requestWithdraw(rebaseToken.target, toEther(0.55), mockWETH.target, toEther(0.55))

        // checking NFT metadata
        const nftAddresss = await exchange.withdrawNft()
        const nft = await ethers.getContractAt("MockERC721", nftAddresss);

        for (let id of [1, 2]) {
            const uri = await nft.tokenURI(id)
            expect(uri.includes(`VaporFund Withdraw NFT #${id}`)).to.true
        }

        // approving
        await exchange.connect(operator).approveRequestWithdraw([1, 2])

        // preparing for withdraw
        await mockWETH.mintTo(exchange.target, toEther(2))

        // withdrawing
        await rebaseToken.connect(bob).approve(exchange.target, ethers.MaxUint256)
        await rebaseToken.connect(charlie).approve(exchange.target, ethers.MaxUint256)

        await nft.connect(bob).approve(exchange.target, 1)
        await nft.connect(charlie).approve(exchange.target, 2)

        await exchange.connect(bob).withdraw(1)
        await exchange.connect(charlie).withdraw(2)

        // verifying
        expect(await mockWETH.balanceOf(bob.address)).to.equal(toEther(0.55))
        expect(await mockWETH.balanceOf(charlie.address)).to.equal(toEther(0.55))
        expect(await rebaseToken.balanceOf(vault.target)).to.equal(toEther(1.1))
    })

    it("should admin withdraw liquidity success", async function () {

        // withdraw remaining WETH on the exchange back to the vault
        let currentBalance = await mockWETH.balanceOf(exchange.target)
        expect(currentBalance).to.equal(toEther(0.9))

        await exchange.connect( operator ).withdrawLiquidity( mockWETH.target, currentBalance )
         
        expect(await mockWETH.balanceOf(exchange.target)).to.equal(0)
    })

})