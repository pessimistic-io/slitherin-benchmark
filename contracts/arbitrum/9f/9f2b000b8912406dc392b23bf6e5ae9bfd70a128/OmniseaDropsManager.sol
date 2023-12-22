// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma abicoder v2;

import "./ReentrancyGuard.sol";
import {MintParams} from "./ERC721Structs.sol";
import "./IOmniseaONFT721Psi.sol";
import "./IOmniseaDropsRepository.sol";

contract OmniseaDropsManager is ReentrancyGuard {
    event Minted(address collection, address minter, uint256 quantity, uint256 value);

    uint256 private _fee;
    address private _revenueManager;
    address private _owner;
    IOmniseaDropsRepository private _repository;

    modifier onlyOwner() {
        require(msg.sender == _owner);
        _;
    }

    constructor(address _repo) {
        _owner = msg.sender;
        _revenueManager = address(0x61104fBe07ecc735D8d84422c7f045f8d29DBf15);
        _repository = IOmniseaDropsRepository(_repo);
    }

    function setFee(uint256 fee) external onlyOwner {
        require(fee <= 20);
        _fee = fee;
    }

    function setRevenueManager(address _manager) external onlyOwner {
        _revenueManager = _manager;
    }

    function mint(MintParams calldata _params) external payable nonReentrant {
        require(_params.collection != address(0) && _params.quantity > 0);
        require(isDrop(_params.collection));
        IOmniseaONFT721Psi collection = IOmniseaONFT721Psi(_params.collection);

        uint256 price = collection.mintPrice(_params.phaseId);
        uint256 quantityPrice = price * _params.quantity;
        if (price > 0) {
            require(msg.value == quantityPrice, "!=price");

            (bool p1,) = payable(collection.getOwner()).call{value: (msg.value * (100 - _fee) / 100)}("");
            require(p1, "!p1");

            if (_fee > 0) {
                (bool p2,) = payable(_revenueManager).call{value: (msg.value * _fee / 100)}("");
                require(p2, "!p2");
            }
        }
        collection.mint(msg.sender, _params.quantity, _params.merkleProof, _params.phaseId);

        emit Minted(_params.collection, msg.sender, _params.quantity, msg.value);
    }

    function isDrop(address _collection) internal returns (bool) {
        return _repository.collections(_collection);
    }

    receive() external payable {}
}

