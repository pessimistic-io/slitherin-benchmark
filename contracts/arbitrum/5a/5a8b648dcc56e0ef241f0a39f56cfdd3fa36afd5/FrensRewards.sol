// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ERC1155.sol";
import "./Ownable.sol";
import "./Utils.sol";

interface IFren {
    function balanceOf(address) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);
}

contract FrensRewards is ERC1155, Ownable {
    string public name;
    string public symbol;

    mapping(uint => string) public tokenURI;
    GM frensGM;
    address public NFA_ERC721 = 0x249bB0B4024221f09d70622444e67114259Eb7e8;
    address public NFA_ERC20 = 0x54cfe852BEc4FA9E431Ec4aE762C33a6dCfcd179;
    uint256 public NFAreward = 420 * 10 ** 18;
    uint256 public frenGmAmount = 1;
    mapping(uint256 => mapping(address => bool)) public hasBurned;
    mapping(uint256 => uint256) public idRewardBonus;

    constructor() ERC1155("") {
        name = "Fungible Frens Rewards";
        symbol = "FFR";
        frensGM = GM(NFA_ERC721);
        idRewardBonus[0] = 1;
    }

    function mint(address _to, uint _id, uint _amount) external onlyOwner {
        _mint(_to, _id, _amount, "");
    }

    function mintBatch(address _to, uint[] memory _ids, uint[] memory _amounts) external onlyOwner {
        _mintBatch(_to, _ids, _amounts, "");
    }

    function setVar(uint256 frenGM, uint256 nfareward) external onlyOwner {
        NFAreward = nfareward;
        frenGmAmount = frenGM;
    }

    function setBonus(uint256 id, uint256 bonus) external onlyOwner {
        idRewardBonus[id] = bonus;
    }

    function somethingAboutTokens(address token) external onlyOwner {
        uint256 balance = IFren(token).balanceOf(address(this));
        IFren(token).transfer(msg.sender, balance);
    }

    function burn(uint _id, uint _amount) external {
        _burn(msg.sender, _id, _amount);
    }

    function frenGM() external returns (uint256) {
        uint256 gmAmount = frensGM.user_GM(msg.sender);
        return gmAmount;
    }

    function burnForNFA(uint _id, uint _amount) external {
        uint256 gmAmount = frensGM.user_GM(msg.sender);
        require(gmAmount > frenGmAmount, "Not Enough GM's");
        require(!hasBurned[_id][msg.sender], "Fren Already Burned for this collection");
        uint256 reward = idRewardBonus[_id] * gmAmount * NFAreward * _amount;
        _burn(msg.sender, _id, _amount);
        hasBurned[_id][msg.sender] = true;
        IFren(NFA_ERC20).transfer(msg.sender, reward);
    }

    function burnBatch(uint[] memory _ids, uint[] memory _amounts) external {
        _burnBatch(msg.sender, _ids, _amounts);
    }

    function burnForMint(
        address _from,
        uint[] memory _burnIds,
        uint[] memory _burnAmounts,
        uint[] memory _mintIds,
        uint[] memory _mintAmounts
    ) external onlyOwner {
        _burnBatch(_from, _burnIds, _burnAmounts);
        _mintBatch(_from, _mintIds, _mintAmounts, "");
    }

    function setURI(uint _id, string memory _uri) external onlyOwner {
        tokenURI[_id] = _uri;
        emit URI(_uri, _id);
    }

    function uri(uint _id) public view override returns (string memory) {
        return tokenURI[_id];
    }
}

