// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Ownable.sol";
import "./ERC721A.sol";

contract Pixxies is Ownable, ERC721A {
    uint256 public MAX_AMOUNT = 3333;
    uint256 public _maxMintable = 5;
    uint256 public _maxFreeAmount = 1111;
    bool public _saleIsActive = false;
    string private _nftBaseURI =
        "ar://heZIYoKvInWgFirfAL1tOK09sLAZfkHs45Dvv51tqLw/";
    uint256 public _listingPrice = 0.002 ether;
    mapping(address => uint256) private balances;

    constructor() ERC721A("Pixxies", "PX") {}

    function setMaxFreeAmount(uint256 maxFreeAmount_) public onlyOwner {
        _maxFreeAmount = maxFreeAmount_;
    }

    function setMaxMintable(uint256 maxMintable_) public onlyOwner {
        _maxMintable = maxMintable_;
    }

    function setListingPrice(uint256 listingPrice_) public onlyOwner {
        _listingPrice = listingPrice_;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _nftBaseURI;
    }

    function setBaseURI(string calldata newURI) public onlyOwner {
        _nftBaseURI = newURI;
    }

    function flipSaleState() public onlyOwner {
        _saleIsActive = !_saleIsActive;
    }

    function withdraw() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function mint(uint256 _amount) public payable {
        require(_saleIsActive, "Sale not active");
        require(totalSupply() + _amount <= (MAX_AMOUNT), "supply limited");
        if (totalSupply() >= _maxFreeAmount) {
            require(
                msg.value >= (_listingPrice * _amount),
                "not enough funds submitted"
            );
        }
        require(
            balances[msg.sender] + _amount <= _maxMintable,
            "Can`t claim more than two tokens"
        );

        balances[msg.sender] += _amount;
        _safeMint(msg.sender, _amount);
    }
}

