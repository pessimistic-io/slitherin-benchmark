// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC20} from "./ERC20.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";
import {DateTimeLib} from "./DateTimeLib.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {Ownable} from "./Ownable.sol";
import {LibBitmap} from "./LibBitmap.sol";
import {MerkleProofLib} from "./MerkleProofLib.sol";
import {LinearVRGDA} from "./LinearVRGDA.sol";

import {Bakery} from "./Bakery.sol";
import {CBT} from "./CBT.sol";

import "./console.sol";

contract Bread is ERC20, Ownable, LinearVRGDA {
    using FixedPointMathLib for uint256;
    using LibBitmap for LibBitmap.Bitmap;

    event Claimed(address indexed user, uint256 amount);

    error NoMoreBread();

    uint256 public constant maxSupply = 12 * 10 ** 9 * 10 ** 18; // 12 billion
    uint256 public constant targetPricePerToken = 0.00000055 ether;
    uint256 public constant devTax = 400;
    address immutable dev;

    uint256 public toSell = 114 * 10 ** 8 * 10 ** 18; // 11.4 billion
    uint256 public tokensSold; // not scaled by 1e18
    uint256 public startTime;

    Bakery public bakery;
    CBT public cbt;

    LibBitmap.Bitmap internal claims;
    bytes32 internal merkleRoot; // 1.5% airdropped

    // goes down 10% per unit of time
    // aiming to sell 20% of tokens per unit of time
    // 1 unit of time = 1 hour
    constructor() LinearVRGDA(int256(targetPricePerToken), 0.1e18, 2280000000 * 10 ** 18) {
        _initializeOwner(msg.sender);
        dev = msg.sender;
        startTime = block.timestamp;
        bakery = new Bakery();
        cbt = new CBT(100000); // 10% CW

        _mint(msg.sender, 420000000 * 10 ** 18); // premint 3.5% for cex
    }

    // ######################################
    // ######################################

    function name() public pure override returns (string memory) {
        return "bread";
    }

    function symbol() public pure override returns (string memory) {
        return "BREAD";
    }

    // ######################################
    // ######################################

    function taxRate() public view returns (uint256 bps) {
        // max 10%, min 0%
        bps = 1000 - (bakery.totalStaked().divWadUp(totalSupply()) / 10 ** 15);
    }

    function getTimePassed() internal view returns (int256 t) {
        t = int256(DateTimeLib.diffHours(startTime, block.timestamp)) * 1e18;
    }

    function getPrice() external view returns (uint256 price) {
        price = getVRGDAPrice(getTimePassed(), tokensSold);
    }

    function getClaimed(uint256 index) external view returns (bool) {
        return claims.get(index);
    }

    // ######################################
    // ######################################

    /// @param tokensToBuy The amount of tokens to buy, not scaled by 1e18
    function buyBread(uint256 tokensToBuy) external payable {
        uint256 tokensToBuyScaled = tokensToBuy * 1e18;
        toSell -= tokensToBuyScaled;
        uint256 price = getVRGDAPrice(getTimePassed(), tokensSold);
        tokensSold += tokensToBuy;
        require(msg.value >= tokensToBuy * price, "UNDERPAID");
        _mint(msg.sender, tokensToBuyScaled);
        SafeTransferLib.safeTransferETH(msg.sender, msg.value - tokensToBuy * price);
        // dev tax
        SafeTransferLib.safeTransferETH(dev, ((tokensToBuy * price) * devTax) / 10000);
    }

    function claim(uint256 index, uint256 amount, bytes32[] calldata proof) external payable {
        require(!claims.get(index), "Already claimed.");
        bytes32 node = keccak256(abi.encodePacked(msg.sender, index, amount));
        require(MerkleProofLib.verify(proof, merkleRoot, node), "Invalid proof.");
        claims.set(index);
        _mint(msg.sender, amount);
        emit Claimed(msg.sender, amount);
    }

    // ######################################
    // ######################################

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        address _staking = address(bakery);
        uint256 _taxRate = taxRate();
        // take tax for stakers
        uint256 tax;
        if (to != _staking && to != address(cbt)) {
            tax = (amount * _taxRate) / 10000;
            // burn 80% of tax
            super._burn(from, (tax * 8000) / 10000);
            // 20% left sent to bakery contract
            super.transferFrom(from, _staking, (tax * 2000) / 10000);
        }
        return super.transferFrom(from, to, amount - tax);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        address _staking = address(bakery);
        uint256 _taxRate = taxRate();
        // take tax for stakers
        uint256 tax;
        if (msg.sender != _staking && msg.sender != address(cbt)) {
            tax = (amount * _taxRate) / 10000;
            // burn 80% of tax
            super._burn(msg.sender, (tax * 8000) / 10000);
            // 20% left sent to bakery contract
            super.transfer(_staking, (tax * 2000) / 10000);
        }
        return super.transfer(to, amount - tax);
    }

    // ######################################
    // ######################################

    function startCBT() external onlyOwner {
        cbt.start{value: address(this).balance}();
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }
}

