// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

interface IMasterChef {
    function mintRewards(address _receiver, uint256 _amount) external;
}

contract gSHEKEL is ERC20("gSHEKEL", "gSHEKEL"), Ownable, ReentrancyGuard { 
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    uint256 public rewardRate;
    address public masterChef;
    address public _operator;

    mapping(address => bool) public minters;

    constructor() {
        _operator = msg.sender;
    }

    modifier onlyMinter() {
        require(minters[msg.sender] == true, "Only minters allowed");
        _;
    }

    modifier onlyMasterChef() {
        require(msg.sender == masterChef, "Caller is not MasterChef contract");
        _;
    }

    modifier onlyOperator() {
        require(_operator == msg.sender, "operator: caller is not the operator");
        _;
    }

    function mint(address recipient_, uint256 amount_) external onlyMinter returns (bool) {
        _mint(recipient_, amount_);
        return true;
    }

    function burn(uint256 _amount) external  {
        _burn(msg.sender, _amount);
    }

    function setRewardRate(uint256 _rewardRate) public onlyMasterChef {
        rewardRate = _rewardRate;
    }

    function setMasterChef(address _masterChef) public onlyOwner {
        masterChef = _masterChef;
    }

    function transferOperator(address newOperator_) public onlyOwner {
        _transferOperator(newOperator_);
    }

    function _transferOperator(address newOperator_) internal {
        require(newOperator_ != address(0), "operator: zero address given for new operator");
        _operator = newOperator_;
    }

    function setMinters(address _minter, bool _canMint) public onlyOperator {
        minters[_minter] = _canMint;
    }

}

