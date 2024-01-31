// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "./ERC721A.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./Address.sol";
import "./IEscrow.sol";
import "./IProduct.sol";

contract Product is IProduct,ERC721A,Ownable {
    using SafeMath for uint256;
    // max supply
    uint256 public maxSupply = 74000000; 

    // product's total sold
    mapping(uint256 => uint256) private prodTotalSold;

    // product's success sold
    mapping(uint256 => uint256) private prodSuccessSold;

    // product's success rate
    mapping(uint256 => uint8) private prodSuccessRate;

    // product available status
    mapping(uint256 => bool) private prodIsBlocked;

    // mint event
    event Mint(
        uint256 indexed productId
    );

    // update sold event
    event UpdateSold(
        uint256 indexed productId,
        bool indexed ifSuccess
    );

    // escrow contract address
    address payable public escrowAddress;

    constructor()  ERC721A("Marketing Rights Of Dejob Products", "PROD")  {

    }

    function _baseURI() internal view virtual override returns (string memory) {
        return "https://dejob.io/api/dejobio/v1/nftproduct/";
    }



    function contractURI() public pure returns (string memory) {
        return "https://dejob.io/api/dejobio/v1/contract/product";
    }

    // override start index to 1
    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    // get product total sold
    function getProdTotalSold(uint256 productId) public view returns(uint256) {
        return prodTotalSold[productId];
    }

    // get product success sold
    function getProdSuccessSold(uint256 productId) public view returns(uint256) {
        return prodSuccessSold[productId];
    }

    // get product success sold rate
    function getProdSuccessRate(uint256 productId) public view returns(uint8) {
        return prodSuccessRate[productId];
    }

    // set escrow contract address
    function setEscrow(address payable _escrow) public onlyOwner {
        IEscrow EscrowContract = IEscrow(_escrow);
        require(EscrowContract.getProductAddress()==address(this),'PROD: wrong escrow contract address');
        escrowAddress = _escrow; 
    }

    // mint new products
    function mint(uint256 quantity) public onlyOwner payable {
        uint256 tokenId                     = super.totalSupply().add(quantity);
        require(tokenId <= maxSupply, 'PROD: supply reach the max limit!');
        _mint(msg.sender, quantity);
    }

    // get product's total supply
    function getMaxProdId() external view override returns(uint256) {
        return super.totalSupply();
    }

    // get product's owner
    function getProdOwner(uint256 prodId) external view override returns(address) {
        require(prodId <= super.totalSupply(),'PROD: illegal product ID!');
        return ownerOf(prodId);
    }

    // get product's block status
    function isProductBlocked(uint256 prodId) external view override returns(bool) {
        require(prodId <= prodId,'PROD: illegal product ID');
        return prodIsBlocked[prodId];
    }

    // block product
    function blockProduct(uint256 productId) public {
        require(ownerOf(productId)==_msgSender(),'PROD: only product owner can block');
        require(productId <= totalSupply()&&!prodIsBlocked[productId],'PROD: wrong product id ');
        prodIsBlocked[productId] = true;
    }

    // unblock product
    function unblockProduct(uint256 productId) public {
        require(ownerOf(productId)==_msgSender(),'PROD: only product owner can block');
        require(productId <= totalSupply()&&prodIsBlocked[productId],'PROD: wrong product id ');
        prodIsBlocked[productId] = false;
    }

    // update product's sold score
    function updateProdScore(uint256 prodId, bool ifSuccess) external override returns(bool) {
        //Only Escrow contract can increase score
        require(escrowAddress == msg.sender,'Prod: only escrow contract can update product sold score');
        //total score add 1
        prodTotalSold[prodId] = prodTotalSold[prodId].add(1);
        if(ifSuccess) {
            // success score add 1
            prodSuccessSold[prodId] = prodSuccessSold[prodId].add(1);
        } else {
            // nothing changed
        }
        // recount product success rate
        prodSuccessRate[prodId] = uint8(prodSuccessSold[prodId].mul(100).div(prodTotalSold[prodId]));
        // emit event
        emit UpdateSold(
            prodId,
            ifSuccess
        );
        return true;

    }

}
