// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ERC1155.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IERC1155.sol";
import "./Utils.sol";

interface IFren {
    function balanceOf(address) external view returns (uint256);

    function burn(uint _id, uint _amount) external;

    function transfer(address to, uint256 amount) external returns (bool);
}

contract FrenLP_Rewards is Ownable, ReentrancyGuard {
    string public name;
    string public symbol;

    mapping(uint => string) public tokenURI;
    GM frensGM;
    address public NFA_ERC721 = 0x249bB0B4024221f09d70622444e67114259Eb7e8;
    address public NFA_ERC20 = 0x54cfe852BEc4FA9E431Ec4aE762C33a6dCfcd179;
    address public NFA_ERC1155 = 0x5A8b648dcc56e0eF241f0a39f56cFdD3fa36AfD5;
    uint256 public rewardNFA = 420000 * 10 ** 18;
    uint256 public frenGmAmount = 1;
    uint256 public div = 1000;
    uint256 public ClaimedAmount = 0;
    uint256 public ClaimDecrease = 9;
    mapping(uint256 => mapping(address => bool)) public hasBurned;
    mapping(uint256 => uint256) public idRewardBonus;

    constructor() {
        frensGM = GM(NFA_ERC721);
    }

    function setBonus(
        uint256 _rewardNFA,
        uint256 id,
        uint256 bonus,
        uint256 _div,
        uint256 _ClaimDecrease
    ) external onlyOwner {
        idRewardBonus[id] = bonus;
        div = _div;
        ClaimDecrease = _ClaimDecrease;
        rewardNFA = _rewardNFA;
    }

    function somethingAboutTokens(address token) external onlyOwner {
        uint256 balance = IFren(token).balanceOf(address(this));
        IFren(token).transfer(msg.sender, balance);
    }

    function frenGM() external returns (uint256) {
        uint256 gmAmount = frensGM.user_GM(msg.sender);
        return gmAmount;
    }

    function burnForNFA(uint _id, uint _amount) external nonReentrant {
        uint256 gmAmount = frensGM.user_GM(msg.sender);
        require(gmAmount > frenGmAmount, "Not Enough GM's");
        require(!hasBurned[_id][msg.sender], "Fren Already Burned for this collection");
        uint256 pre_reward = (idRewardBonus[_id] * gmAmount * rewardNFA * _amount) / div;
        uint256 reward = (pre_reward * (100 - ClaimedAmount * ClaimDecrease)) / 100;
        IERC1155(NFA_ERC1155).safeTransferFrom(msg.sender, address(this), _id, _amount, "");
        IFren(NFA_ERC1155).burn(_id, _amount);
        hasBurned[_id][msg.sender] = true;
        ClaimedAmount++;
        IFren(NFA_ERC20).transfer(msg.sender, reward);
    }

    // required function to allow receiving ERC-1155
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external returns (bytes4) {
        return bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"));
    }
}

