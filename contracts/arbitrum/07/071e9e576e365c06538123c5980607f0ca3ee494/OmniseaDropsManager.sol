// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma abicoder v2;

import "./ReentrancyGuard.sol";
import {MintParams} from "./ERC721Structs.sol";
import "./IOmniseaERC721Psi.sol";
import "./IOmniseaDropsFactory.sol";

contract OmniseaDropsManager is ReentrancyGuard {
    event Minted(address collection, address minter, uint256 quantity, uint256 value);

    uint256 public fixedFee;
    uint256 private _fee;
    address private _revenueManager;
    address private _owner;
    bool private _isPaused;
    IOmniseaDropsFactory private _factory;

    modifier onlyOwner() {
        require(msg.sender == _owner);
        _;
    }

    constructor(address factory_) {
        _owner = msg.sender;
        _revenueManager = address(0x61104fBe07ecc735D8d84422c7f045f8d29DBf15);
        _factory = IOmniseaDropsFactory(factory_);
        _fee = 4;
        fixedFee = 250000000000000;
    }

    function setFee(uint256 fee) external onlyOwner {
        require(fee <= 20);
        _fee = fee;
    }

    function setFixedFee(uint256 fee) external onlyOwner {
        fixedFee = fee;
    }

    function setRevenueManager(address _manager) external onlyOwner {
        _revenueManager = _manager;
    }

    function mint(MintParams calldata _params) external payable nonReentrant {
        require(!_isPaused);
        require(_factory.drops(_params.collection));
        IOmniseaERC721Psi collection = IOmniseaERC721Psi(_params.collection);

        uint256 price = collection.mintPrice(_params.phaseId);
        uint256 quantityPrice = price * _params.quantity;
        require(msg.value == quantityPrice + fixedFee, "!=price");
        if (quantityPrice > 0) {
            uint256 paidToOwner = quantityPrice * (100 - _fee) / 100;
            (bool p1,) = payable(collection.owner()).call{value: paidToOwner}("");
            require(p1, "!p1");

            (bool p2,) = payable(_revenueManager).call{value: msg.value - paidToOwner}("");
            require(p2, "!p2");
        } else {
            (bool p3,) = payable(_revenueManager).call{value: msg.value}("");
            require(p3, "!p3");
        }
        collection.mint(msg.sender, _params.quantity, _params.merkleProof, _params.phaseId);

        emit Minted(_params.collection, msg.sender, _params.quantity, msg.value);
    }

    function setPause(bool isPaused_) external onlyOwner {
        _isPaused = isPaused_;
    }

    function withdraw() external onlyOwner {
        (bool p,) = payable(_owner).call{value: address(this).balance}("");
        require(p, "!p");
    }

    receive() external payable {}
}

