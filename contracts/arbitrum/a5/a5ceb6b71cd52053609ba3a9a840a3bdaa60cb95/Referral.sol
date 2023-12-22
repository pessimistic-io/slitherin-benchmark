// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./SafeERC20.sol";
import "./Ownable.sol";

abstract contract ReferralEvents {
    event UpdateGame(address game, bool state);
    event CreateReferralCode(
        address player,
        uint256 referralId,
        string referralCode
    );
    event UpdateCommission(uint256 referralId, uint256 commission);
    event UpdateReferralCodeByUser(address player, string code);
}

contract Referral is ReferralEvents, Ownable {
    using SafeERC20 for IERC20;

    mapping(address => bool) enabledGames;
    mapping(address => uint256) public usedReferralCodes;

    uint256 public ids;
    mapping(string => uint256) public referralIds;
    mapping(uint256 => string) public referralCodes;
    mapping(uint256 => address) public referralOwner;

    //to calculate downlines off-chain we need a commission to start with.
    mapping(uint256 => uint256) public baseCommissions;

    constructor() {}

    function createCode(string calldata code) public {
        require(referralIds[code] == 0, "code already taken");
        ++ids;

        referralCodes[ids] = code;
        referralIds[code] = ids;
        referralOwner[ids] = msg.sender;

        emit CreateReferralCode(msg.sender, ids, code);
    }

    function setBaseCommissions(
        uint256[] calldata _referralIds,
        uint256[] calldata _commissions
    ) public onlyOwner {
        require(_referralIds.length == _commissions.length, "invalid arrays");

        for (uint256 index = 0; index < _referralIds.length; index++) {
            baseCommissions[_referralIds[index]] = _commissions[index];

            emit UpdateCommission(_referralIds[index], _commissions[index]);
        }
    }

    function updateUser(address player, uint256 referralId) public {
        if (
            (referralId == 0) ||
            (enabledGames[msg.sender] == false) ||
            (usedReferralCodes[player] != 0)
        ) {
            return;
        }
        usedReferralCodes[player] = referralId;
    }

    function setReferralCodeByUser(string memory code) external {
        require(referralIds[code] != 0, "code id is 0");
        usedReferralCodes[msg.sender] = referralIds[code];
        emit UpdateReferralCodeByUser(msg.sender, code);
    }

    function getCodeId(
        string memory code,
        address player
    ) external view returns (uint256) {
        if (usedReferralCodes[player] != 0) return usedReferralCodes[player];
        return referralIds[code];
    }

    function toggleGames(
        address[] calldata games,
        bool[] calldata toggles
    ) external onlyOwner {
        require(games.length == toggles.length, "invalid arrays");

        for (uint256 index = 0; index < games.length; index++) {
            enabledGames[games[index]] = toggles[index];

            emit UpdateGame(games[index], toggles[index]);
        }
    }

    function recoverToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(msg.sender, amount);
    }
}

