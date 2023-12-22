//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {IMasterChefV2, UserStruct, IRewarder} from "./IMasterChefV2.sol";
import {Ownable} from "./Ownable.sol";
import {IERC20} from "./IERC20.sol";

contract PatchOfThePatch is IMasterChefV2, Ownable {
    mapping(address => bool) public isAdapter;

    uint256 public constant DPX_FARM_PID = 17;
    uint256 public constant RDPX_FARM_PID = 23;

    address public constant DPX_LP = 0x0C1Cf6883efA1B496B01f654E247B9b419873054;
    address public constant RDPX_LP =
        0x7418F5A2621E13c05d1EFBd71ec922070794b90a;

    mapping(uint256 => mapping(address => uint256)) public balances;

    function adminDeposit(
        address _to,
        uint256 _amount,
        uint256 _pid
    ) external onlyOwner {
        if (_pid == DPX_FARM_PID) {
            IERC20(DPX_LP).transferFrom(msg.sender, address(this), _amount);
        } else {
            IERC20(RDPX_LP).transferFrom(msg.sender, address(this), _amount);
        }

        balances[_pid][_to] = _amount;
    }

    constructor(address[] memory _adapters) {
        for (uint256 i; i < _adapters.length; i++) {
            isAdapter[_adapters[i]] = true;
        }
    }

    function userInfo(
        uint256 _pid,
        address _user
    ) external view override returns (UserStruct.UserInfo memory) {
        return UserStruct.UserInfo(balances[_pid][_user], 0);
    }

    function pendingSushi(
        uint256 _pid,
        address _user
    ) external view override returns (uint256 pending) {}

    function deposit(
        uint256 pid,
        uint256 amount,
        address to
    ) external override {
        require(isAdapter[msg.sender], "onlyAdapter()");

        if (pid == DPX_FARM_PID) {
            IERC20(DPX_LP).transferFrom(msg.sender, address(this), amount);
        } else {
            IERC20(RDPX_LP).transferFrom(msg.sender, address(this), amount);
        }

        balances[pid][msg.sender] = balances[pid][msg.sender] + amount;
    }

    function withdraw(
        uint256 pid,
        uint256 amount,
        address to
    ) external override {
        require(isAdapter[msg.sender], "onlyAdapter()");

        if (pid == DPX_FARM_PID) {
            IERC20(DPX_LP).transfer(to, amount);
        } else {
            IERC20(RDPX_LP).transfer(to, amount);
        }

        balances[pid][msg.sender] = balances[pid][msg.sender] - amount;
    }

    function harvest(uint256 pid, address to) external override {}

    function withdrawAndHarvest(
        uint256 pid,
        uint256 amount,
        address to
    ) external override {
        require(isAdapter[msg.sender], "onlyAdapter()");

        if (pid == DPX_FARM_PID) {
            IERC20(DPX_LP).transfer(to, amount);
        } else {
            IERC20(RDPX_LP).transfer(to, amount);
        }

        balances[pid][msg.sender] = balances[pid][msg.sender] - amount;
    }

    function rescue(IERC20 _token, uint256 _amount) external onlyOwner {
        _token.transfer(msg.sender, _amount);
    }

    function updateMapping(
        address _adapter,
        bool _authorized
    ) external onlyOwner {
        isAdapter[_adapter] = _authorized;
    }

    function rewarder(
        uint256 _pid
    ) external view override returns (IRewarder) {}
}

