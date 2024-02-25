//SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./MockRToken.sol";
import "../interfaces/IMockDepositPool.sol";
import "../interfaces/etherfi/IeTH.sol";

import "hardhat/console.sol";

contract MockDepositPool is IMockDepositPool {

    MockRToken public rToken;

    constructor() {
        rToken = new MockRToken();
    }

    function rTokenAddress() external view returns (address) {
        return address(rToken);
    }

    function deposit() external payable returns (uint256) {
        return rToken.mintTo{value: msg.value}(msg.sender);
    }

    function withdraw(address recipient, uint256 amount) external returns (uint256) {
        
        IeETH token = IeETH(address(rToken));
        token.transferFrom(msg.sender, address(this), amount);

        return rToken.burn(recipient, amount);
    }

    function rebase(int128 _accruedRewards) external {
        rToken.rebase(_accruedRewards);
    }

    function addEthAmountLockedForWithdrawal() external payable {
        require( msg.value > 0, "invalid value");
    }

}