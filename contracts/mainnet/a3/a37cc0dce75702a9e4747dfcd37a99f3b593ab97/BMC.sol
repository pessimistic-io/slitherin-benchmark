//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./ERC721.sol";
import "./IERC20.sol";

import "./IBMC.sol";
import "./IPriceStrategy.sol";

import "./Validator.sol";
import "./Killswitch.sol";
import "./CCAcceptERC20.sol";

contract BMC is CCAcceptERC20, ERC721, IBMC, Validator, Killswitch {
    uint256 private _tokenNum;
    uint256 private constant MAX_SUPPLY = 6000;

    string private _baseUri;
    uint256 private _salesStartTimestamp = 0;

    modifier sales() {
        // solhint-disable-next-line not-rely-on-time
        require(_salesStartTimestamp > 0 && block.timestamp >= _salesStartTimestamp, "sales not started");
        _;
    }

    constructor(string memory name_, string memory symbol_
        , address priceStrategy
        , address erc20Contract
        )
        CCAcceptERC20(erc20Contract, priceStrategy)
        ERC721(name_, symbol_)
        // solhint-disable-next-line no-empty-blocks
    {
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseUri;
    }

    function setBaseUri(string memory baseUri) external override onlyOwner {
        _baseUri = baseUri;
    }

    function setERC20PriceStrategy(address erc20Contract, address priceStrategyAddress) public override onlyOwner {
        _setERC20PriceStrategy(erc20Contract, priceStrategyAddress);
    }

    function setSalesStartAt(uint256 timestamp) external override onlyOwner {
        _salesStartTimestamp = timestamp;
    }

    function totalSupply() public override view returns (uint256) {
        return _tokenNum;
    }

    function maxSupply() public override pure returns (uint256) {
        return MAX_SUPPLY;
    }

    function getERC20Price(address erc20Contract, uint256 tokenNum) public view override erc20ok(erc20Contract) returns (uint256)
    {
        return _getERC20Price(erc20Contract, tokenNum);
    }

    function getSalesStartAt() external view override returns (uint256) {
        return _salesStartTimestamp;
    }

    function mintForERC20(address erc20Contract, uint256 amount) external override erc20ok(erc20Contract) killswitch sales {
        uint256 price = getERC20Price(erc20Contract, _tokenNum);
        IERC20 erc20 = IERC20(erc20Contract);
        uint256 allowance = erc20.allowance(msg.sender, address(this));
        require(allowance >= price * amount, "low allowance");
        uint256 balance = erc20.balanceOf(msg.sender);
        require(balance >= price * amount, "low balance");

        // transfer directly to owner
        bool success = erc20.transferFrom(msg.sender, owner(), amount * price);
        require(success, "failed to transfer erc20");

        _mintImpl(msg.sender, amount);
    }

    function _mintImpl(address for_, uint256 amount) private {
        require(amount > 0 && amount <= 20, "can't mint 0 or above 20 per tx");
        require(_tokenNum + amount <= MAX_SUPPLY, "can't mint above MAX_SUPPLY");

        uint256 _initial = _tokenNum + 1;
        for (uint256 i = 0; i < amount; ++i) {
            _safeMint(for_, _initial + i);
        }
        _tokenNum += amount;
    }

    function validatorMintNew(address mintFor, uint256 amount) external override onlyValidator killswitch {
        _mintImpl(mintFor, amount);
    }

    function validatorMint(address mintFor, uint256 tokenId) external override onlyValidator killswitch {
        require(mintFor != address(0), "invalid mintFor");
        require(tokenId <= _tokenNum, "not allowed: totalSupply");
        _safeMint(mintFor, tokenId);
    }

    function validatorBurn(uint256 tokenId) external override onlyValidator killswitch {
        _burn(tokenId);
    }

    function withdraw() external override onlyOwner {
        uint256 value = address(this).balance;
        if (value > 0) {
            address payable to = payable(owner());
            to.transfer(value);
        }
    }
}

