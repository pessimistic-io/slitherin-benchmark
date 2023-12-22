// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./AddressUpgradeable.sol";
import "./Initializable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IOperators.sol";

contract AirdropForHyperVLP is Initializable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct AirdropInfo {
        address account;
        uint256 amount;
    }

    IOperators public operators;

    address private vela;

    event AirdropDistributed(address indexed account, uint256 amount);

    modifier onlyOperator(uint256 level) {
        require(operators.getOperatorLevel(msg.sender) >= level, "invalid operator");
        _;
    }

    /* ========== INITIALIZE FUNCTIONS ========== */

    function initialize(address _operators, address _vela) public initializer {
        require(AddressUpgradeable.isContract(_operators), "operators invalid");

        operators = IOperators(_operators);
        vela = _vela;
    }

    function distributeAirdrops(AirdropInfo[] calldata _airdrops) external onlyOperator(3) {
        uint256 length = _airdrops.length;
        for (uint256 i; i < length; ) {
            // IERC20Upgradeable(vela).safeTransfer(_airdrops[i].account, _airdrops[i].amount);
            emit AirdropDistributed(_airdrops[i].account, _airdrops[i].amount);
            unchecked {
                ++i;
            }
        }
    }

    function rescueToken(address _token, uint256 _amount) external onlyOperator(4) {
        IERC20Upgradeable(_token).safeTransfer(msg.sender, _amount);
    }
}
