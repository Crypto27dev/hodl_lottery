// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract HodlNFT is ERC721, Ownable {
    address private RewardWallet;
   
    event SetHodlNFTPrice(address addr, uint256 newNFTPrice);
    event SetBaseURI(address addr, string newUri);
    event SetHodlNFTURI(address addr, string newUri);
    event SetRewardWalletAddress(address addr, address rewardWallet);

    using Strings for uint256;

    uint256 private HODL_NFT_PRICE                          = 10;     //HODL token

    using Counters for Counters.Counter;
    Counters.Counter private _hodlTokenCounter;
    
    string private _baseURIExtended;

    string private hodlNFTURI;

    /**
    * @dev Throws if called by any account other than the multi-signer.
    */
    // modifier onlyMultiSignWallet() {
    //     require(owner() == _msgSender(), "Multi-signer: caller is not the multi-signer");
    //     _;
    // }
    
    constructor() ERC721("HODL NFT","HNFT") {
        _baseURIExtended = "https://ipfs.infura.io/";
    }

    function setRewardWalletAddress(address _newRewardWallet) external onlyOwner{
        RewardWallet = _newRewardWallet;
        emit SetRewardWalletAddress(msg.sender, _newRewardWallet);
    }

    //Set, Get Price Func
    function setHodlNFTPrice(uint256 _newNFTValue) external onlyOwner{
        HODL_NFT_PRICE = _newNFTValue;
        emit SetHodlNFTPrice(msg.sender, _newNFTValue);
    }

    function getHodlNFTPrice() external view returns(uint256){
        return HODL_NFT_PRICE;
    }

    function getHodlNFTURI() external view returns(string memory){
        return hodlNFTURI;
    }

    function setHodlNFTURI(string memory _hodlNFTURI) external onlyOwner{
        hodlNFTURI = _hodlNFTURI;
        emit SetHodlNFTURI(msg.sender, hodlNFTURI);
    }

   /**
    * @dev Mint NFT by customer
    */
    function mintNFT(address sender) external returns (uint256) {

        require( msg.sender == RewardWallet, "you can't mint from other account");

        // Incrementing ID to create new token
        uint256 newHodlNFTID = _hodlTokenCounter.current();
        _hodlTokenCounter.increment();

        _safeMint(sender, newHodlNFTID);
        return newHodlNFTID;
    }

    /**
     * @dev Return the base URI
     */
     function _baseURI() internal override view returns (string memory) {
        return _baseURIExtended;
    }

    /**
     * @dev Set the base URI
     */
    function setBaseURI(string memory baseURI_) external onlyOwner() {
        _baseURIExtended = baseURI_;
        emit SetBaseURI(msg.sender, baseURI_);
    }
}