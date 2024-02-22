//SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import {Constants} from "./utility/Constants.sol";

/*
 * @title MultiSigVault
 * @dev a vault contract responsible for locking tokens on the parent chain and storing tokens on the child chain for any purpose. it requires multi-signature for withdrawals.
 */

contract MultiSigVault is ReentrancyGuard {
    using Address for address;
    using SafeERC20 for IERC20;

    struct Transaction {
        address tokenAddress;
        address to;
        uint value;
        bool executed;
        uint numConfirmations;
    }

    Transaction[] public transactions;

    address[] public operators;
    mapping(address => bool) public isOperator;

    uint8 public numConfirmationsRequired;

    // mapping from tx index => owner => bool
    mapping(uint => mapping(address => bool)) public isConfirmed;

    event Deposit(
        address indexed sender,
        address tokenAddress,
        uint amount,
        uint balance
    );
    event SubmitTransaction(
        address indexed tokenAddress,
        address indexed sender,
        uint indexed txIndex,
        address to,
        uint value
    );
    event ConfirmTransaction(
        address indexed tokenAddress,
        address indexed sender,
        uint indexed txIndex
    );
    event RevokeConfirmation(
        address indexed tokenAddress,
        address indexed sender,
        uint indexed txIndex
    );
    event ExecuteTransaction(
        address indexed tokenAddress,
        address indexed sender,
        uint indexed txIndex
    );

    constructor(address[] memory _operators, uint8 _numConfirmationsRequired) {
        require(_operators.length > 0, "operators required");
        require(
            _numConfirmationsRequired > 0 &&
                _numConfirmationsRequired <= _operators.length,
            "invalid number of required confirmations"
        );

        for (uint8 i = 0; i < _operators.length; i++) {
            address operator = _operators[i];

            require(operator != address(0), "invalid operator");
            require(!isOperator[operator], "operator not unique");

            isOperator[operator] = true;
            operators.push(operator);
        }

        numConfirmationsRequired = _numConfirmationsRequired;
    }

    /// @notice deposit native ETH by just transferring to this contract
    receive() external payable {
        emit Deposit(
            msg.sender,
            Constants.ETH_TOKEN,
            msg.value,
            address(this).balance
        );
    }

    /// @notice deposit ERC-20 tokens
    function depositWithERC20(
        address _token,
        uint256 _amount
    ) public nonReentrant {
        require(_token != Constants.ETH_TOKEN, "invalid token address");

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(
            msg.sender,
            _token,
            _amount,
            IERC20(_token).balanceOf(address(this))
        );
    }

    /// @notice deposit with ETH
    function depositWithETH() payable public nonReentrant  {
        emit Deposit(
            msg.sender,
            Constants.ETH_TOKEN,
            msg.value,
            address(this).balance
        );
    }

    /// @notice submit a withdrawal request
    function submitTransaction(
        address _token,
        address _to,
        uint _value
    ) public onlyOperator nonReentrant {
        uint txIndex = transactions.length;

        if (_token == Constants.ETH_TOKEN) {
            require(address(this).balance >= _value, "insufficent funds");
        } else {
            require(
                IERC20(_token).balanceOf(address(this)) >= _value,
                "insufficent funds"
            );
        }

        transactions.push(
            Transaction({
                tokenAddress: _token,
                to: _to,
                value: _value,
                executed: false,
                numConfirmations: 0
            })
        );

        emit SubmitTransaction(_token, msg.sender, txIndex, _to, _value);
    }

    /// @notice operators confirm the pending request
    function confirmTransaction(uint _txIndex)
        public
        onlyOperator
        txExists(_txIndex)
        notExecuted(_txIndex)
        notConfirmed(_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];
        transaction.numConfirmations += 1;
        isConfirmed[_txIndex][msg.sender] = true;

        emit ConfirmTransaction(transaction.tokenAddress, msg.sender, _txIndex);
    }

    /// @notice executing when it has sufficient confirmation
    function executeTransaction(uint _txIndex) public onlyOperator txExists(_txIndex) notExecuted(_txIndex) {
        Transaction storage transaction = transactions[_txIndex];

        require(
            transaction.numConfirmations >= numConfirmationsRequired,
            "cannot execute tx"
        );

        transaction.executed = true;

        if (transaction.tokenAddress == Constants.ETH_TOKEN) {
            (bool sent, ) = transaction.to.call{value: transaction.value}("");
            require(sent, "tx failed");
        } else {
            IERC20(transaction.tokenAddress).safeTransfer(transaction.to, transaction.value);
        }

        emit ExecuteTransaction(transaction.tokenAddress, msg.sender, _txIndex);
    }

    /// @notice cancel a pending request
    function revokeConfirmation(uint _txIndex) public onlyOperator txExists(_txIndex) notExecuted(_txIndex) {
        Transaction storage transaction = transactions[_txIndex];

        require(isConfirmed[_txIndex][msg.sender], "tx not confirmed");

        transaction.numConfirmations -= 1;
        isConfirmed[_txIndex][msg.sender] = false;

        emit RevokeConfirmation(transaction.tokenAddress, msg.sender, _txIndex);
    }

    function getOperators() public view returns (address[] memory) {
        return operators;
    }

    function getTransaction(uint _txIndex)
        public
        view
        returns (
            address tokenAddress,
            address to,
            uint value,
            bool executed,
            uint numConfirmations
        )
    {
        Transaction storage transaction = transactions[_txIndex];

        return (
            transaction.tokenAddress,
            transaction.to,
            transaction.value,
            transaction.executed,
            transaction.numConfirmations
        );
    }

    function getTransactionCount() public view returns (uint) {
        return transactions.length;
    }

    /****************************************
     *          INTERNAL FUNCTIONS          *
     ****************************************/

    modifier onlyOperator() {
        require(isOperator[msg.sender], "only operator");
        _;
    }

    modifier txExists(uint _txIndex) {
        require(_txIndex < transactions.length, "tx does not exist");
        _;
    }

    modifier notExecuted(uint _txIndex) {
        require(!transactions[_txIndex].executed, "tx already executed");
        _;
    }

    modifier notConfirmed(uint _txIndex) {
        require(!isConfirmed[_txIndex][msg.sender], "tx already confirmed");
        _;
    }
}
