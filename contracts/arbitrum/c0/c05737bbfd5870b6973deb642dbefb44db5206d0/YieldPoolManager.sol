// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity =0.8.18;

import "./Ownable.sol";
import "./SafeERC20.sol";

import "./IVirtualBalanceRewardPool.sol";
import "./ITreasury.sol";

contract YieldPoolManager is Ownable {
    using SafeERC20 for IERC20;

    uint public immutable PRECISION = 10000;

    IERC20 public immutable wstETH;
    ITreasury public immutable treasury;
    IVirtualBalanceRewardPool public immutable pool;

    uint public bondYieldPercentage;
    mapping(address => bool) public isManager;

    constructor(IERC20 _wstETH, ITreasury _treasury, IVirtualBalanceRewardPool _pool, uint _bondYieldPercentage) {
        wstETH = _wstETH;
        treasury = _treasury;
        pool = _pool;
        bondYieldPercentage = _bondYieldPercentage;
    }

    modifier onlyManager() {
        require(isManager[msg.sender], "!auth");
        _;
    }

    function updateBondYieldPercentage(uint _bondYieldPercentage) external onlyOwner {
        bondYieldPercentage = _bondYieldPercentage;
    }

    function setManager(address[] calldata managers, bool[] calldata status) external onlyOwner {
        require(managers.length == status.length, "!data");
        unchecked {
            for (uint8 i; i < managers.length; i++) {
                isManager[managers[i]] = status[i];
            }
        }
    }

    function updateBondYield() external onlyManager {
        uint balance = wstETH.balanceOf(address(treasury));
        uint yield = (balance * bondYieldPercentage) / PRECISION;
        treasury.addDebt(address(wstETH), balance);
        wstETH.safeTransfer(address(pool), yield);
        pool.notifyRewardAmount(yield);
        wstETH.safeTransfer(owner(), balance - yield);
    }

    function addRewardToPool(uint amount) external onlyManager {
        wstETH.safeTransferFrom(msg.sender, address(pool), amount);
        pool.notifyRewardAmount(amount);
    }
}

