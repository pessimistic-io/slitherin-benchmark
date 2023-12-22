// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./ERC20Burnable.sol";

import "./Operator.sol";

contract SARB is ERC20Burnable, Operator {
    using SafeMath for uint256;

    //TOTAL MAX SUPPLY = 50,000 SARBs
    uint256 public constant FARMING_POOL_REWARD_ALLOCATION = 14500 ether;


    bool public rewardPoolDistributed = false;

    /**
     * @notice Constructs the SARB (Share ARB) ERC-20 contract.
     */
    constructor() ERC20("SARB", "SARB") {
        _mint(msg.sender, 500 ether); // mint 500 SARB for initial pools deployment
    }
    /**
     * @notice distribute to reward pool (only once)
     */
    function distributeReward(address _farmingIncentiveFund) external onlyOperator {
        require(!rewardPoolDistributed, "only can distribute once");
        require(_farmingIncentiveFund != address(0), "!_farmingIncentiveFund");
        rewardPoolDistributed = true;
        _mint(_farmingIncentiveFund, FARMING_POOL_REWARD_ALLOCATION);
    }

    function burn(uint256 amount) public override {
        super.burn(amount);
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        _token.transfer(_to, _amount);
    }
}
