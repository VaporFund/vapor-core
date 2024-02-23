//SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./interfaces/IMultiSigController.sol";

import { Constants } from "./utility/Constants.sol";

/*
 * @title Vault
 * @dev a vault contract responsible for locking tokens for any purpose. 
 */

interface IWithdraw {
    function withdraw(address _token, uint256 _amount, address _recipient) external;
}

contract Vault is ReentrancyGuard {
    using Address for address;
    using SafeERC20 for IERC20;

    IMultiSigController public controller;

    event Deposit(
        address indexed sender,
        address indexed tokenAddress,
        uint amount,
        uint balance
    );

    event RequestWithdraw(
        address indexed operator,
        address indexed tokenAddress,
        uint amount,
        address recipient,
        uint32 requestId
    );

    event Withdraw(
        address indexed tokenAddress,
        uint amount,
        uint balance
    );

    constructor(address _controller) {
        controller = IMultiSigController(_controller);
    }

    /// @notice deposit native ETH
    receive() external payable {
        emit Deposit(
            msg.sender,
            Constants.ETH_TOKEN,
            msg.value,
            address(this).balance
        );
    }

    /// @notice another way to deposit native ETH
    function depositWithETH() payable external nonReentrant  {
        emit Deposit(
            msg.sender,
            Constants.ETH_TOKEN,
            msg.value,
            address(this).balance
        );
    }

    /// @notice deposit ERC-20 tokens
    function depositWithERC20(address _token, uint256 _amount) external nonReentrant {
        require(_token != Constants.ETH_TOKEN, "ETH should be called another func.");

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(
            msg.sender,
            _token,
            _amount,
            IERC20(_token).balanceOf(address(this))
        );
    }

    /// @notice submit a withdrawal request
    function requestWithdraw(address _token, uint256 _amount, address _recipient) external onlyOperator {
        require( controller.isOperator(msg.sender), "unauthorized");

        if (_token == Constants.ETH_TOKEN) {
            require(address(this).balance >= _amount, "insufficent funds");
        } else {
            require(
                IERC20(_token).balanceOf(address(this)) >= _amount,
                "insufficent funds"
            );
        }

        uint32 currentRequestId = controller.submitRequest(abi.encodeCall(IWithdraw.withdraw, (_token, _amount, _recipient)));

        emit RequestWithdraw(msg.sender, _token, _amount, _recipient, currentRequestId);
    }

    /// @notice perform withdrawal
    function withdraw(address _token, uint256 _amount, address _recipient) external onlyController {
        if (_token == Constants.ETH_TOKEN) {
            (bool sent, ) = _recipient.call{value: _amount}("");
            require(sent, "sent ETH failed");

            emit Withdraw(_token, _amount, address(this).balance);
        } else {
            IERC20(_token).safeTransfer(_recipient, _amount);
            emit Withdraw(_token, _amount, IERC20(_token).balanceOf(address(this)));
        }
    }

    /****************************************
     *          INTERNAL FUNCTIONS          *
     ****************************************/

    modifier onlyController() {
        require(msg.sender == address(controller), "only controller");
        _;
    }

    modifier onlyOperator() {
        require(controller.isOperator(msg.sender), "only operator");
        _;
    }

}