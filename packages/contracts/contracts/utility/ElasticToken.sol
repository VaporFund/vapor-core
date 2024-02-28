// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/*
 * @title ElasticToken
 * @dev a elastic bridge token aimed to be deployed on the child chain replicates assets from the parent chain, tokens can be minted, rebased and burned per the calldata received via vault.sol, basically forking from ether.fi's eETH
 */

abstract contract Ownable {
    event OwnershipTransferred(address indexed user, address indexed newOwner);

    error Unauthorized();
    error InvalidOwner();

    address public owner;

    modifier onlyOwner() virtual {
        if (msg.sender != owner) revert Unauthorized();

        _;
    }

    constructor(address _owner) {
        if (_owner == address(0)) revert InvalidOwner();

        owner = _owner;

        emit OwnershipTransferred(address(0), _owner);
    }

    function transferOwnership(address _owner) public virtual onlyOwner {
        if (_owner == address(0)) revert InvalidOwner();

        owner = _owner;

        emit OwnershipTransferred(msg.sender, _owner);
    }

    function revokeOwnership() public virtual onlyOwner {
        owner = address(0);

        emit OwnershipTransferred(msg.sender, address(0));
    }
}

contract ElasticToken is ReentrancyGuard, Ownable {

    /// @dev token metadata
    string public name;
    string public symbol;
    uint8 public decimals;

    /// @dev rebase variants
    uint256 public totalShares;
    mapping (address => uint256) public shares;
    mapping (address => mapping (address => uint256)) public allowances;

    uint128 public totalValueOut;
    uint128 public totalValueIn;

    error InvalidAmount(); 
    error SendFail();

    event TransferShares( address indexed from, address indexed to, uint256 sharesValue);

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _owner
    ) Ownable(_owner) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }


    /// @dev approve the token spender similar to ERC-20 tokens
    function approve(address _spender, uint256 _amount) public nonReentrant returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    /// @dev transfer tokens to recipient address
    function transfer(address _recipient, uint256 _amount) public returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    /// @dev transfer tokens from the spender to the recipient address
    function transferFrom(address _sender, address _recipient, uint256 _amount) external returns (bool) {
        uint256 currentAllowance = allowances[_sender][msg.sender];
        require(currentAllowance >= _amount, "TRANSFER_AMOUNT_EXCEEDS_ALLOWANCE");
        unchecked {
            _approve(_sender, msg.sender, currentAllowance - _amount);
        }
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    function decreaseAllowance(address _spender, uint256 _decreaseAmount) public nonReentrant returns (bool) {
        address owner = msg.sender;
        uint256 currentAllowance = allowance(owner, _spender);
        require(currentAllowance >= _decreaseAmount, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, _spender, currentAllowance - _decreaseAmount);
        }
        return true;
    }

    function increaseAllowance(address _spender, uint256 _increaseAmount) public nonReentrant returns (bool) {
        address owner = msg.sender;
        uint256 currentAllowance = allowance(owner, _spender);
        _approve(owner, _spender,currentAllowance + _increaseAmount);
        return true;
    }

    function allowance(address _owner, address _spender) public view returns (uint256) {
        return allowances[_owner][_spender];
    }

    /// @dev mint tokens to the caller 
    function mint(uint256 _amount) external onlyOwner returns (uint256) {
        return _mint(msg.sender, _amount, 0);
    }

    /// @dev mint tokens to the given address
    function mintTo(address _recipient, uint256 _amount) external onlyOwner returns (uint256) {
        return _mint(_recipient, _amount, 0);
    }

    /// @dev burn tokens on the given address
    function burn(address _recipient, uint256 _amount) external onlyOwner returns (uint256) {
        uint256 share = sharesForWithdrawalAmount(_amount);
        if (_amount > type(uint128).max || _amount == 0 || share == 0) revert InvalidAmount();

        totalValueIn -= uint128(_amount);
        
        _burnShares(_recipient, share);

        return share;
    }

    /// @dev rebase the supply by providing taken rewards
    function rebase(int128 _accruedRewards) public {
        totalValueOut = uint128(int128(totalValueOut) + _accruedRewards);
    }

    /// @dev check the user balance
    function balanceOf(address _user) public view returns (uint256) {
        return getTotalValueClaimOf(_user);
    }


    function getTotalValueClaimOf(address _user) public view returns (uint256) {
        uint256 staked;
        if (totalShares > 0) {
            staked = (getTotalPooledValue() * shares[_user]) / totalShares;
        }
        return staked;
    }

    function getTotalPooledValue() public view returns (uint256) {
        return totalValueIn + totalValueOut;
    }

    function _mint(address _recipient, uint256 _amountIn, uint256 _amountOut) internal returns (uint256) {
        totalValueIn += uint128(_amountIn);
        totalValueOut += uint128(_amountOut);
        uint256 amount = _amountIn + _amountOut;
        uint256 share = _sharesForMintAmount(amount);
        if (amount > type(uint128).max || amount == 0 || share == 0) revert InvalidAmount();

        _mintShares(_recipient, share);

        return share;
    }
    
    function _mintShares(address _user, uint256 _share) internal {
        shares[_user] += _share;
        totalShares += _share;
    }

    function _burnShares(address _user, uint256 _share) internal {
        require(shares[_user] >= _share, "BURN_AMOUNT_EXCEEDS_BALANCE");
        shares[_user] -= _share;
        totalShares -= _share;
    }

    function _transfer(address _sender, address _recipient, uint256 _amount) internal {
        uint256 _sharesToTransfer = _sharesForAmount(_amount);
        _transferShares(_sender, _recipient, _sharesToTransfer); 
    }

    function _sharesForMintAmount(uint256 _mintAmount) internal view returns (uint256) {
        uint256 totalPooledValue = getTotalPooledValue() - _mintAmount;
        if (totalPooledValue == 0) {
            return _mintAmount;
        }
        return (_mintAmount * totalShares) / totalPooledValue;
    }

    function sharesForWithdrawalAmount(uint256 _amount) internal view returns (uint256) {
        uint256 totalPooledValue = getTotalPooledValue();
        if (totalPooledValue == 0) {
            return 0;
        }

        // ceiling division so rounding errors favor the protocol
        uint256 numerator = _amount * totalShares;
        return (numerator + totalPooledValue - 1) / totalPooledValue;
    }

    function _sharesForAmount(uint256 _amount) internal view returns (uint256) {
        uint256 totalPooledValue = getTotalPooledValue();
        if (totalPooledValue == 0) {
            return 0;
        }
        return (_amount * totalShares) / totalPooledValue;
    }

    function _transferShares(address _sender, address _recipient, uint256 _sharesAmount) internal {
        require(_sender != address(0), "TRANSFER_FROM_THE_ZERO_ADDRESS");
        require(_recipient != address(0), "TRANSFER_TO_THE_ZERO_ADDRESS");
        require(_sharesAmount <= shares[_sender], "TRANSFER_AMOUNT_EXCEEDS_BALANCE");

        shares[_sender] -= _sharesAmount;
        shares[_recipient] += _sharesAmount;
    }

    function _approve(address _owner, address _spender, uint256 _amount) internal {
        require(_owner != address(0), "APPROVE_FROM_ZERO_ADDRESS");
        require(_spender != address(0), "APPROVE_TO_ZERO_ADDRESS");

        allowances[_owner][_spender] = _amount; 
    }

    

    



}