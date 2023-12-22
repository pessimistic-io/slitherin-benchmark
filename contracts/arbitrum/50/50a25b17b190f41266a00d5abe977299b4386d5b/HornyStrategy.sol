// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./IERC20.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./Context.sol";
import "./Address.sol";

interface IGBT {
    function repayMax() external;

    function repaySome(uint256 _amount) external;

    function borrowMax() external;

    function borrowSome(uint256 _amount) external;

    function sell(
        uint256 _amountGBT,
        uint256 _minETH,
        uint256 expireTimestamp
    ) external;

    function buy(
        uint256 _amountBASE,
        uint256 _minGBT,
        uint256 expireTimestamp
    ) external;

    function debt(address account) external view returns (uint256);

    function borrowCredit(address account) external view returns (uint256);

    function currentPrice() external view returns (uint256);
}

interface IXGBT {
    function depositToken(uint256 amount) external;

    function withdrawToken(uint256 amount) external;

    function getRewardForDuration(address _rewardsToken)
        external
        view
        returns (uint256);

    function earned(address account, address _rewardsToken)
        external
        view
        returns (uint256);

    function rewardPerToken(address _rewardsToken)
        external
        view
        returns (uint256);

    function lastTimeRewardApplicable(address _rewardsToken)
        external
        view
        returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function balanceOfNFT(address user)
        external
        view
        returns (uint256 length, uint256[] memory arr);

    function getReward() external;
}

pragma solidity 0.8.13;

contract HornyStrategy is Ownable, Pausable {
    using SafeERC20 for IERC20;
    using Address for address;

    // Tokens
    address public want;
    address public output;
    address public output2;

    // Third party contracts
    address public xgbt;

    // Hyena addresses
    address public strategist;
    address public vault;

    // Fees
    uint256 public constant FEE_DIVISOR = 1000;
    uint256 public constant WITHDRAW_FEE = 1; // 0.1%
    uint256 public constant CALL_FEE = 1; // 0.1%
    uint256 public constant PLATFORM_FEE = 30; // 3%

    constructor(
        address _want,
        address _output,
        address _output2,
        address _xgbt
    ) {
        strategist = msg.sender;
        want = _want;
        output = _output;
        output2 = _output2;
        xgbt = _xgbt;
    }

    function deposit() public whenNotPaused {
        require(msg.sender == vault, "!auth");
        _deposit();
    }

    function _deposit() internal whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        approveTxnIfNeeded(want, xgbt, wantBal);

        if (wantBal > 0) {
            IXGBT(xgbt).depositToken(wantBal);
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IXGBT(xgbt).withdrawToken(_amount - wantBal);
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        uint256 withdrawalFeeAmount = (wantBal * WITHDRAW_FEE) / FEE_DIVISOR;
        IERC20(want).safeTransfer(vault, wantBal - withdrawalFeeAmount);
    }

    function beforeDeposit() external virtual {
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        approveTxnIfNeeded(want, xgbt, wantBal);

        if (wantBal > 0) {
            IXGBT(xgbt).depositToken(wantBal);
        }
    }

    function harvest() external virtual {
        require(msg.sender == tx.origin, "!Auth");
        _harvest(msg.sender);
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    function _harvest(address _caller) internal {
        getReward();
        compoundRewards();
        chargeFees(_caller);
        _deposit();
    }

    function compoundRewards() internal {
        uint256 output2Bal = IERC20(output2).balanceOf(address(this));
        approveTxnIfNeeded(output2, want, output2Bal);
        IGBT(want).buy(output2Bal, 1, 0);
    }

    function getReward() internal {
        IXGBT(xgbt).getReward();
    }

    function chargeFees(address _caller) internal {
        uint256 callerFee = IERC20(want).balanceOf(address(this)) * CALL_FEE / FEE_DIVISOR;
        uint256 platformFee = IERC20(want).balanceOf(address(this)) * PLATFORM_FEE / FEE_DIVISOR;
        IERC20(want).transfer(_caller, callerFee);
        IERC20(want).transfer(strategist, platformFee);
    }

    function harvestRewardEnHorny() public view returns (uint256) {
        uint256 horny = IXGBT(xgbt).earned(address(this), want);
        uint256 weth = IXGBT(xgbt).earned(address(this), output2);

        uint256 reward = (((weth / IGBT(want).currentPrice()) + horny) * CALL_FEE) / FEE_DIVISOR;

        return reward;
    }

    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function balanceOfPool() public view returns (uint256) {
        uint256 _amount = IXGBT(xgbt).balanceOf(address(this));
        return _amount;
    }

    function retireStrat() external {
        require(msg.sender == vault, "!vault");
        IXGBT(xgbt).withdrawToken(balanceOfPool());

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    function panic() external onlyOwner {
        pause();
        IXGBT(xgbt).withdrawToken(balanceOfPool());
    }

    function pause() public onlyOwner {
        _pause();

        IERC20(want).safeApprove(xgbt, 0);
    }

    function unpause() external onlyOwner {
        _unpause();
        _deposit();
    }

    function approveTxnIfNeeded(
        address _token,
        address _spender,
        uint256 _amount
    ) internal {
        if (IERC20(_token).allowance(address(this), _spender) < _amount) {
            IERC20(_token).safeApprove(_spender, 0);
            IERC20(_token).safeApprove(_spender, 9999000000000000000000);
        }
    }
}

