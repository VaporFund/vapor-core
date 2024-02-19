const { ethers } = require("ethers")

exports.fromEther = (value) => {
    return Number(ethers.formatEther(value))
}

exports.fromUsdc = (value) => {
    return ethers.formatUnits(value, 6)
}

exports.toEther = (value) => {
    return ethers.parseEther(`${value}`)
}

exports.toUsdc = (value) => {
    return ethers.parseUnits(`${value}`, 6)
}