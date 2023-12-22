// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./IERC20.sol";
import "./IDToken.sol";
import "./IPool.sol";
import "./SafeERC20.sol";
import "./Admin.sol";

contract AirdropPToken is Admin {

    event ClaimPToken(address account, uint256 pTokenId);

    using SafeERC20 for IERC20;

    address public immutable bToken;

    address public immutable pool;

    address public immutable pToken;

    uint256 public immutable amount;

    int256 public immutable volume;

    mapping (address => bool) public whitelist;

    constructor (address bToken_, address pool_, uint256 amount_, int256 volume_) {
        bToken = bToken_;
        pool = pool_;
        amount = amount_;
        volume = volume_;
        pToken = address(IPool(pool_).pToken());
        IERC20(bToken_).safeApprove(pool_, type(uint256).max);
    }

    function updateWhiteList(address[] calldata accounts, bool allowance) external _onlyAdmin_ {
        for (uint256 i = 0; i < accounts.length; i++) {
            whitelist[accounts[i]] = allowance;
        }
    }

    function withdraw(address to) external _onlyAdmin_ {
        IERC20(bToken).safeTransfer(to, IERC20(bToken).balanceOf(address(this)));
    }

    function claimPToken() external {
        require(whitelist[msg.sender], 'AirdropPToken.claimPToken: not in white list');

        IPool(pool).addMargin(bToken, amount, new IPool.OracleSignature[](0));
        uint256 pTokenId = IDToken(pToken).getTokenIdOf(address(this));
        require(pTokenId > 0, 'AirdropPToken.claimPToken: no pToken');

        if (pTokenId % 2 == 0) {
            IPool(pool).trade('BTCUSD', volume, type(int256).max, new IPool.OracleSignature[](0));
        } else {
            IPool(pool).trade('BTCUSD', -volume, 0, new IPool.OracleSignature[](0));
        }

        IDToken(pToken).transferFrom(address(this), msg.sender, pTokenId);
        emit ClaimPToken(msg.sender, pTokenId);
    }

}

