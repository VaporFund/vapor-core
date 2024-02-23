const { ethers } = require("hardhat")
const { expect } = require("chai")

describe("#multiSignController", () => {

    let controller
    let callme

    let alice
    let bob
    let charlie
    let dave

    before(async () => {

        [alice, bob, charlie, dave] = await ethers.getSigners()

        const MultiSigController = await ethers.getContractFactory("MultiSigController")
        const CallMe = await ethers.getContractFactory("CallMe")

        controller = await MultiSigController.deploy([alice.address, bob.address], 2)
        callme = await CallMe.deploy(controller.target)
    })

    it("should add and remove new operators success", async function () {
        
        let operators = await controller.getOperators()
        expect(operators.length).to.equal(2)

        // add charlie and dave
        await controller.connect(alice).addOperator(charlie.address)
        await controller.connect(alice).addOperator(dave.address)

        operators = await controller.getOperators()
        expect(operators.length).to.equal(4)

        // remove alice and bob
        await controller.connect(alice).removeOperator(alice.address)
        await controller.connect(alice).removeOperator(bob.address)

        operators = await controller.getOperators()
        expect(operators.filter(item => item !== ethers.ZeroAddress).length).to.equal(2)

        // transfer admin permission
        await controller.connect(alice).transferAdmin(bob.address)
        
        // alice shouldn't able to add anymore
        try {
            await controller.connect(alice).addOperator(bob.address)
        } catch (e) { 
            expect(e.message.includes("unauthorized")).to.true
        }
    })

    it("should received request submission from another contract success", async function () {
        
        // add supported contract
        await controller.connect(dave).addContract(callme.target)

        // submit 3 requests
        await callme.submit()
        await callme.submit()
        await callme.submit()

        // now approve and execute all of them
        for (let i= 0; i < 3; i++) {
            await controller.connect(charlie).confirmRequest(i)
            await controller.connect(dave).confirmRequest(i)

            await controller.connect(dave).executeRequest(i)
        }

        // result should equal 123+123+123
        expect(await callme.i()).to.equal(369n)

    })

    
    
})