//SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "hardhat/console.sol";

/*
 * @title WithdrawRequestNFT
 * @dev NFT ERC-721 represents a withdrawal request
 */

contract WithdrawRequestNFT is ERC721URIStorage {
    
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    address public exchange;

    /// @dev mapping of token ID to token address for withdrawal
    mapping(uint256 => address) private tokenAddresses;

    /// @dev mapping of token ID to withdrawal amount
    mapping(uint256 => uint256) private tokenAmount;

    constructor(address _exchange) ERC721("Withdraw Request NFT", "WithdrawRequestNFT") {
        exchange = _exchange;
    }

    function mint(address _token, uint256 _amount, address _recipient) external onlyExchange returns (uint256) {
        _tokenIds.increment();

        uint256 newItemId = _tokenIds.current();

        _mint(_recipient, newItemId);

        tokenAddresses[newItemId] = _token;
        tokenAmount[newItemId] = _amount;
        return newItemId;
    }

    /// @dev transfering locked tokens to the given address
    function withdrawTo(address _token, uint256 _amount, address _recipient) external onlyExchange {
        IERC20(_token).transfer(_recipient, _amount);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {

            string memory jsonPreImage = string.concat(
                string.concat(
                    string.concat('{"name": "VaporFund Withdraw NFT #', Strings.toString(id)),
                    '","description":"NFT ERC-721 represents a withdrawal request","external_url":"https://www.vaporfund.com","image":"'
                ),
                string.concat("https://picsum.photos/500/500?grayscale")
            );
            string memory jsonPostImage = string.concat(
                '","attributes":[{"trait_type":"Token to be Withdrawal","value":"',
                Strings.toHexString(tokenAddresses[id]),'"},{"trait_type":"Withdraw Amount","value":"',
                Strings.toString(tokenAmount[id])
            );
            string memory jsonPostTraits = '"}]}';

            return
                string.concat(
                    "data:application/json;utf8,",
                    string.concat(
                        string.concat(jsonPreImage, jsonPostImage),
                        jsonPostTraits
                    )
                );
    }

    function getTokenAmount(uint256 id) public view returns (uint256) {
        return tokenAmount[id];
    }

    function getTokenAddress(uint256 id) public view returns (address) {
        return tokenAddresses[id];
    }



    /****************************************
     *          INTERNAL FUNCTIONS          *
     ****************************************/

    modifier onlyExchange() {
        require(msg.sender == address(exchange), "only exchange");
        _;
    }


}