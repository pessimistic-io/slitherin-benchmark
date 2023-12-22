// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ReentrancyGuard.sol";
import "./ERC20.sol";

import "./ICamelotRouter.sol";
import "./IWETH.sol";
import "./ICamelotPair.sol";
import "./ICamelotFactory.sol";

contract DuckCity is ERC20, ReentrancyGuard {

    address public deadAddress = 0x000000000000000000000000000000000000dEaD;
    ICamelotRouter public camelotRouter = ICamelotRouter(0xc873fEcbd354f5A56E00E710B90EF4201db2448d);
    IWETH public WETH = IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    ICamelotPair public camelotPair;

    uint256 public onePiece = 1000000 * 1e18;
//    uint256 public pieceCount = 30000;
    uint256 public pieceCount = 10;

//    uint256 public unitPrice = 0.0005 ether;
    uint256 public unitPrice = 1 wei;
    uint256 public maxUserMint = 6;

    mapping(address => uint256) public userMintCount;
    uint256 public totalMintCount;

    address public creator;

    constructor()  ERC20("TEST Token", "TEST") {
        creator = msg.sender;
    }

    function x() external payable {
        require(msg.value == 0.00001 ether, "Invalid amount");
        totalMintCount ++;
        _mint(address(this), onePiece);
        _approve(address(this), address(camelotRouter), onePiece);
        camelotRouter.addLiquidityETH{value: msg.value}(
            address(this),
            onePiece,
            0,
            0,
            msg.sender,
            block.timestamp
        );
        camelotPair = ICamelotPair(ICamelotFactory(camelotRouter.factory()).getPair(address(this), address(WETH)));
    }


    function withdraw() external {
        require(address(this).balance > 0, "No balance");
        (bool s,) = creator.call{value: address(this).balance}("");
        require(s, "Withdraw failed");
    }

    function mint(uint256 mintCount) external payable {
        require(msg.sender == tx.origin, "Only EOA");
        require(userMintCount[msg.sender] + mintCount <= maxUserMint, "Exceeded maximum mint count per address");
        require(msg.value >= mintCount * unitPrice, "Insufficient ETH");
        require(totalMintCount < pieceCount, "Mint done");

        uint256 mintTokenAmount = mintCount * onePiece;
        _mint(msg.sender, mintTokenAmount);
        _mint(address(camelotPair), mintTokenAmount);
        WETH.deposit{value: unitPrice * mintCount}();
        WETH.transfer(address(camelotPair), unitPrice * mintCount);
        camelotPair.sync();

        userMintCount[msg.sender] += mintCount;
        totalMintCount += mintCount;
    }
}
