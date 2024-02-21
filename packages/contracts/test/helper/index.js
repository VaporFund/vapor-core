const { ethers } = require("ethers")

exports.fromEther = (value) => {
    return Number(ethers.formatEther(value))
}

exports.toEther = (value) => {
    return ethers.parseEther(`${value}`)
}
