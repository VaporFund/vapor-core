const { ethers } = require("hardhat")
const { expect } = require("chai")
const { toEther, fromEther } = require("./helper")

describe("#multiSigVault", () => {

    let vault
    let nonRebaseToken
    let rebaseToken

    let alice
    let bob
    let charlie
    let dave

    before(async () => {

        [alice, bob, charlie, dave] = await ethers.getSigners()

        const MultiSigVault = await ethers.getContractFactory("MultiSigVault")
        const MockERC20 = await ethers.getContractFactory("MockERC20")
        const MockRToken = await ethers.getContractFactory("MockRToken")

        vault = await MultiSigVault.deploy([alice.address, bob.address, charlie.address, dave.address], 2)

        // deploy tokens
        nonRebaseToken = await MockERC20.deploy("Non-Rebase Token", "NON-REBASE", 18)
        rebaseToken = await MockRToken.deploy()
    })

    it("should deposit/withdraw native tokens from/to the vault success", async function () {

        await vault.connect(alice).depositWithETH({ value: toEther(10) })

        await vault.connect(alice).submitTransaction(
            "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
            dave.address,
            toEther(10)
        )

        const request = await vault.getTransaction(0)
        expect(request["tokenAddress"]).to.equal("0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE")
        expect(request["to"]).to.equal("0x90F79bf6EB2c4f870365E785982E1f101E93b906")
        expect(request["value"]).to.equal(10000000000000000000n)
        expect(request["executed"]).to.false

        // signing
        await vault.connect(alice).confirmTransaction(0)
        await vault.connect(bob).confirmTransaction(0)

        // withdrawing
        await vault.connect(charlie).executeTransaction(0)

    })

    it("should deposit/withdraw non-rebase tokens from/to the vault success", async function () {

        // mint and deposit 10,000 NON-REBASE
        await nonRebaseToken.connect(alice).mint(toEther(10000))
        await nonRebaseToken.connect(alice).approve(vault.target, ethers.MaxUint256)

        await vault.connect(alice).depositWithERC20(nonRebaseToken.target, toEther(10000))

        // submit a request
        await vault.connect(alice).submitTransaction(
            nonRebaseToken.target,
            dave.address,
            toEther(10000)
        )

        // signing
        await vault.connect(alice).confirmTransaction(1)
        await vault.connect(bob).confirmTransaction(1)

        // withdrawing
        await vault.connect(charlie).executeTransaction(1)
        
        // checking
        expect(await nonRebaseToken.balanceOf(dave.address)).to.equal(10000000000000000000000n)

    })

    it("should deposit/withdraw rebase tokens from/to the vault success", async function () {

        // mint and deposit 100 REBASE
        await rebaseToken.connect(alice).mint({ value : toEther(100)})
        await rebaseToken.connect(alice).approve(vault.target, ethers.MaxUint256)

        await rebaseToken.connect(bob).mint({ value : toEther(200)})

        await vault.connect(alice).depositWithERC20(rebaseToken.target, toEther(100))

        // submit a request
        await vault.connect(alice).submitTransaction(
            rebaseToken.target,
            dave.address,
            toEther(100)
        )

        // signing
        await vault.connect(alice).confirmTransaction(2)
        await vault.connect(bob).confirmTransaction(2)

        await rebaseToken.rebase( toEther(10) )

        // withdrawing
        await vault.connect(charlie).executeTransaction(2)
        
        // checking  
        expect(fromEther(await rebaseToken.balanceOf(dave.address))).to.be.closeTo(100, 0.1)
        // some rewards still remain in the contract after the rebase
        expect(fromEther(await rebaseToken.balanceOf(vault.target))).to.be.closeTo(3, 0.4)

    })

})

