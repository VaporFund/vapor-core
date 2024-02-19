// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.13;

// import "../interfaces/etherfi/ILiquidityPool.sol";
// import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";

// // wrapper of ILiquidityPool.sol for testing

// contract LiquidityPool is ILiquidityPool {

//     address dummyAddress;
//     uint256 dummyValue;

//     uint32 public numPendingDeposits;
//     uint128 public totalValueOutOfLp;
//     uint128 public totalValueInLp;

//     function addEthAmountLockedForWithdrawal(uint128 _amount) external {
//         dummyValue = uint256(_amount);
//     }

//     function amountForShare(uint256 _share) public view returns (uint256) {
//         return _share;
//     }

//     function batchApproveRegistration() external {}

//     function batchCancelDeposit(uint256[] calldata _validatorIds) external {}

//     function batchCancelDepositByAdmin(
//         uint256[] calldata _validatorIds,
//         address _bnftStaker
//     ) external {}

//     function batchDepositAsBnftHolder(
//         uint256[] calldata _candidateBidIds,
//         uint256 _numberOfValidators
//     ) external payable returns (uint256[] memory) {
//         return _candidateBidIds;
//     }

//     function batchRegisterAsBnftHolder(
//         bytes32 _depositRoot,
//         uint256[] calldata _validatorIds,
//         IStakingManager.DepositData[] calldata _registerValidatorDepositData,
//         bytes32[] calldata _depositDataRootApproval,
//         bytes[] calldata _signaturesForApprovalDeposit
//     ) external {}

//     function decreaseSourceOfFundsValidators(
//         uint32 numberOfEethValidators,
//         uint32 numberOfEtherFanValidators
//     ) external {}

//     // Used by eETH staking flow
//     function deposit() external payable returns (uint256) {
//         return 0;
//     }

//     function deposit(address _referral) public payable returns (uint256) {
//         return 0;
//     }

//     function depositToRecipient(
//         address _recipient,
//         uint256 _amount,
//         address _referral
//     ) public returns (uint256) {
//         return 0;
//     }

//     function deposit(
//         address _user,
//         address _referral
//     ) external payable returns (uint256) {
//         return 0;
//     }

//     function batchApproveRegistration(
//         uint256[] memory _validatorIds,
//         bytes[] calldata _pubKey,
//         bytes[] calldata _signature
//     ) external {}

//     function getTotalEtherClaimOf(
//         address _user
//     ) external view returns (uint256) {
//         return 0;
//     }

//     function getTotalPooledEther() public view returns (uint256) {
//         return 0;
//     }

//     function updateAdmin(address _address, bool _isAdmin) external { }

//     function pauseContract() external {  }

//     function unPauseContract() external {  }

//     function rebase(int128 _accruedRewards) public { }

//     function requestMembershipNFTWithdraw(address recipient, uint256 amount, uint256 fee) public returns (uint256) {
//         return 0;
//     }

//     function requestWithdraw(address recipient, uint256 amount) public returns (uint256) {
//         return 0;
//     }

//     function requestWithdrawWithPermit(address _owner, uint256 _amount, PermitInput calldata _permit) external returns (uint256)
//     { 
//         return 0;
//     }

//     function sendExitRequests(uint256[] calldata _validatorIds) external {
//     }

//     function setStakingTargetWeights(uint32 _eEthWeight, uint32 _etherFanWeight) external {
        
//     }

//     function sharesForAmount(uint256 _amount) public view returns (uint256) {
//         return 0;
//     }

//     function sharesForWithdrawalAmount(uint256 _amount) public view returns (uint256) {
//         return 0;
//     }

//     function withdraw(address _recipient, uint256 _amount) external returns (uint256) {
//         return 0;
//     }

// }
