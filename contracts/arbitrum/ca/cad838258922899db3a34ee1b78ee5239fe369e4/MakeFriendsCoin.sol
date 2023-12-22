// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "./ILauncher.sol";
import "./IMakeFriendCoin.sol";
import "./Ownable.sol";
import "./Math.sol";
import "./ERC20.sol";
import "./ERC20Burnable.sol";

contract MakeFriendsCoin is IMakeFriendCoin, ERC20, ERC20Burnable {
    ILauncher public immutable launcher;

    uint256 public immutable maxTotalSupply;

    modifier onlyLauncher() {
        require(
            address(launcher) == msg.sender,
            "MFC: caller is not the launcher"
        );
        _;
    }

    constructor(ILauncher _launcher) ERC20("Make Friends Coin", "MFC") {
        launcher = _launcher;
        maxTotalSupply = 16_000_000_000 * 10 ** 18;
    }

    function mint(address to, uint256 amount) public onlyLauncher {
        _mint(to, amount);
    }

    function burn(
        uint256 amount
    ) public override(ERC20Burnable, IMakeFriendCoin) {
        _burn(_msgSender(), amount);
    }

    function burnFrom(
        address account,
        uint256 amount
    ) public override(ERC20Burnable, IMakeFriendCoin) {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20) {
        require(!launcher.isBlackList(from), "MFC: from is in black list");
        if (from == address(0)) {
            require(
                totalSupply() + amount <= maxTotalSupply,
                "MFC: total supply exceeds max total supply"
            );
        }

        // unlaunch, only transfer to tribe
        if (!launcher.launchDone()) {
            require(launcher.isAuthorized(to), "MFC: only transfer to tribe");
            if (from != address(0)) {
                require(from != to, "MFC: do not transfer to self");
                require(
                    launcher.getTribeShare2MultiplyRemainTimes(to) > 0,
                    "MFC: target tribe share2earn remain times is zero"
                );
                uint256 share2MultiplyAmount = Math.min(
                    launcher.getShare2MultiplyAmount(from),
                    amount
                );
                uint256 share2earnReward = launcher.computeShare2EarnReward(
                    from,
                    to,
                    share2MultiplyAmount
                );
                launcher.subShare2MultiplyAmount(
                    from,
                    to,
                    share2MultiplyAmount,
                    share2earnReward
                );
                uint256 maxHoldeAmount = launcher.getMaxHoldeAmount();
                require(
                    balanceOf(to) + amount <= maxHoldeAmount,
                    "MFC: target tribe balance exceeds max holde amount"
                );
                require(
                    balanceOf(from) + share2earnReward <= maxHoldeAmount,
                    "MFC: target tribe balance exceeds max holde amount"
                );
                _mint(from, share2earnReward);
            }
        }

        super._beforeTokenTransfer(from, to, amount);
    }
}

