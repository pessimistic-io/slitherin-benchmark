// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ReentrancyGuard.sol";
import "./ERC20.sol";
import "./Ownable.sol";

import "./ICamelotRouter.sol";
import "./IWETH.sol";
import "./ICamelotPair.sol";
import "./ICamelotFactory.sol";

contract FARB is ERC20, ReentrancyGuard, Ownable {
    address public deadAddress = 0x000000000000000000000000000000000000dEaD;
    ICamelotRouter public camelotRouter = ICamelotRouter(0xc873fEcbd354f5A56E00E710B90EF4201db2448d);
    IWETH public WETH = IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    ICamelotPair public camelotPair;

    uint256 public onePiece = 1000000 * 1e18;
    uint256 public pieceCount = 21000;

    uint256 public unitPrice = 0.0003 ether;
    uint256 public maxUserMint = 10;

    mapping(address => uint256) public userMintCount;

    uint256 public totalMintCount;

    address public creator;

    uint256 public startTime = 9999999999;

    constructor()  ERC20("Fair ARB Token", "FARB") {
        creator = msg.sender;
        _mint(address(this), onePiece * pieceCount *2);
    }

    function setStartTime(uint256 _time) external onlyOwner {
        startTime = _time;
    }

    function x() external payable onlyOwner {
        require(msg.value == 0.00001 ether, "Invalid amount");
        require(address(camelotPair) == address(0), "Already initialized");
        totalMintCount ++;
        _approve(address(this), address(camelotRouter), onePiece);
        camelotRouter.addLiquidityETH{value: msg.value}(
            address(this),
            onePiece,
            0,
            0,
            deadAddress,
            block.timestamp
        );
        camelotPair = ICamelotPair(ICamelotFactory(camelotRouter.factory()).getPair(address(this), address(WETH)));
    }

    function disappear() external onlyOwner {
        transferOwnership(deadAddress);
    }

    function withdraw() external {
        require(address(this).balance > 0, "No balance");
        (bool s,) = creator.call{value: address(this).balance}("");
        require(s, "Withdraw failed");
    }

    function mint(uint256 mintCount) external payable {
        require(totalMintCount + mintCount <= pieceCount, "Mint done");
        require(block.timestamp >= startTime, "Not started");
        require(msg.sender == tx.origin, "Only EOA");
        require(userMintCount[msg.sender] + mintCount <= maxUserMint, "Exceeded maximum mint count per address");
        require(msg.value >= mintCount * unitPrice, "Insufficient ETH");

        uint256 mintTokenAmount = mintCount * onePiece;
        // transfer to user
        _transfer(address(this), msg.sender, mintTokenAmount);
        // transfer to lp
        _transfer(address(this), address(camelotPair), mintTokenAmount);
        WETH.deposit{value: unitPrice * mintCount}();
        WETH.transfer(address(camelotPair), unitPrice * mintCount);
        camelotPair.sync();
        userMintCount[msg.sender] += mintCount;
        totalMintCount += mintCount;
    }
}
