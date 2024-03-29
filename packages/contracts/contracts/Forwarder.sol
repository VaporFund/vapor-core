//SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IMultiSigController.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IMockDepositPool.sol";
import "./interfaces/etherfi/ILiquidityPool.sol";

import { IWithdraw } from "./Vault.sol";
import { Constants } from "./utility/Constants.sol";

import "hardhat/console.sol";

/*
 * @title Forwarder
 * @dev a vault contract wrapper that interfaces with external protocols (ether.fi / hashnote) and keeps updating to support additional ones
 */

contract Forwarder is ReentrancyGuard {
    using Address for address;
    using SafeERC20 for IERC20;
    
    enum ProtocolsForStaking {
        MOCK,
        ETHERFI
    }

    /// @dev controller for multi-sig operations
    IMultiSigController public controller;

    /// @dev main's vault on the chain
    IVault public vault;

    /// @dev registry address for all supported protocols
    mapping(ProtocolsForStaking => address) public registry;

    event RequestStake(
        uint32 indexed requestId,
        string stakingProtocol,
        address stakingAddress,
        address tokenAddress,
        uint256 amount,
        address indexed operator
    );

    event RequestUnstake(
        uint32 indexed requestId,
        string stakingProtocol,
        address stakingAddress,
        address tokenAddress,
        uint256 amount,
        address indexed operator
    );

    constructor(address _controller, address _vault) {
        controller = IMultiSigController(_controller);
        vault = IVault(_vault);
    }
 
    /// @notice stake asset from vault in respective protocol, output also locked in vault upon completion
    function requestStake(ProtocolsForStaking _protocol, address _tokenAddress, uint256 _amountIn) external onlyOperator  {
        if (_protocol == ProtocolsForStaking.MOCK) _stakeMock(_tokenAddress, _amountIn);
        if (_protocol == ProtocolsForStaking.ETHERFI) _stakeEtherfi(_amountIn);
    }

    /// @notice request unstaking from the protocol. Alternatively, unstaking manually could better fit most workflows
    function requestUnstake(ProtocolsForStaking _protocol, address _tokenAddress, uint256 _unstakeAmount) external onlyOperator  {
        
        require( IERC20(_tokenAddress).balanceOf(address(vault)) >= _unstakeAmount, "insufficient balance on vault.sol" );
        
        if (_protocol == ProtocolsForStaking.MOCK) _unstakeMock(_tokenAddress, _unstakeAmount);

    }

    /// @notice register the protocol's interface contract address
    function register(ProtocolsForStaking _protocol, address _address) external onlyOperator {
        registry[_protocol] = _address;
    }

    /****************************************
     *          INTERNAL FUNCTIONS          *
     ****************************************/

    function _stakeMock(address _tokenAddress, uint256 _amountIn) internal {

        if (_tokenAddress == Constants.ETH_TOKEN) {
            uint32 currentRequestId = controller.submitRequest(
            address(vault),
            abi.encodeCall( 
                IWithdraw.withdrawAndStake, 
                (_tokenAddress, 
                _amountIn, 
                "MOCK", 
                registry[ProtocolsForStaking.MOCK], 
                abi.encodeCall(IMockDepositPool.deposit, ()))
            ));

            emit RequestStake(currentRequestId, "MOCK", registry[ProtocolsForStaking.MOCK], _tokenAddress, _amountIn, msg.sender);
        } else {
            uint32 currentRequestId = controller.submitRequest(
            address(vault),
            abi.encodeCall( 
                IWithdraw.withdrawAndStake, 
                (_tokenAddress, 
                _amountIn, 
                "MOCK", 
                registry[ProtocolsForStaking.MOCK], 
                abi.encodeCall(IMockDepositPool.depositUsdc, (_amountIn)))
            ));

            emit RequestStake(currentRequestId, "MOCK", registry[ProtocolsForStaking.MOCK], _tokenAddress, _amountIn, msg.sender);
        }

        
    }

    function _unstakeMock(address _tokenAddress, uint256 _unstakeAmount) internal {

        address rTokenAddress = IMockDepositPool(registry[ProtocolsForStaking.MOCK]).rTokenAddress();

        if (_tokenAddress == rTokenAddress) {

            uint32 currentRequestId = controller.submitRequest(
            address(vault),
            abi.encodeCall( 
                IWithdraw.unstake, 
                (_tokenAddress, 
                _unstakeAmount, 
                "MOCK", 
                registry[ProtocolsForStaking.MOCK], 
                abi.encodeCall(IMockDepositPool.withdraw, (address(vault), _unstakeAmount)))
            ));

            emit RequestUnstake(currentRequestId, "MOCK", registry[ProtocolsForStaking.MOCK], _tokenAddress, _unstakeAmount, msg.sender);

        } else {

            uint32 currentRequestId = controller.submitRequest(
            address(vault),
            abi.encodeCall( 
                IWithdraw.unstake, 
                (_tokenAddress, 
                _unstakeAmount, 
                "MOCK", 
                registry[ProtocolsForStaking.MOCK], 
                abi.encodeCall(IMockDepositPool.withdrawUsdc, (address(vault), _unstakeAmount)))
            ));

            emit RequestUnstake(currentRequestId, "MOCK", registry[ProtocolsForStaking.MOCK], _tokenAddress, _unstakeAmount, msg.sender);

        }
    }

    function _stakeEtherfi(uint256 _amountIn) internal {
        uint32 currentRequestId = controller.submitRequest(
            address(vault),
            abi.encodeCall( 
                IWithdraw.withdrawAndStake, 
                (Constants.ETH_TOKEN, 
                _amountIn, 
                "ETHERFI", 
                registry[ProtocolsForStaking.ETHERFI], 
                abi.encodeCall(ILiquidityPool.deposit, ()))
            ));

        emit RequestStake(currentRequestId, "ETHERFI", registry[ProtocolsForStaking.ETHERFI], Constants.ETH_TOKEN, _amountIn, msg.sender);
    }

    modifier onlyOperator() {
        require(controller.isOperator(msg.sender), "only operator");
        _;
    }


}