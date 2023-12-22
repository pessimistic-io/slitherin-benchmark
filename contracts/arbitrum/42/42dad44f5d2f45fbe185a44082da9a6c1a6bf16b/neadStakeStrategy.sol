// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AccessControlEnumerable.sol";
import "./IERC20.sol";
import "./Initializable.sol";

import "./INeadStake.sol";
import "./IRamsesV2Pool.sol";
import "./IVotingEscrow.sol";
import "./IXRam.sol";

contract neadStakeStrategy is Initializable, AccessControlEnumerable {
    bytes32 public constant TIMELOCK_ROLE = keccak256("TIMELOCK_ROLE");
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");

    address public constant neadStake =
        0x7D07A61b8c18cb614B99aF7B90cBBc8cD8C72680;
    address public constant asset = 0x40301951Af3f80b8C1744ca77E55111dd3c1dba1;
    address public constant votingEscrow =
        0xAAA343032aA79eE9a6897Dab03bef967c3289a06;
    address public constant xRam = 0xAAA1eE8DC1864AE49185C368e8c64Dd780a50Fb7;
    address public platformFeeReceiver;
    address public vault;
    address[] rewards;

    uint constant basis = 1000;
    uint public treasuryFee;
    uint public harvestFee;

    // Mirrored from TickMath
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO =
        1461446703485210103287273052203988822378723970342;

    struct routeInfo {
        address pool;
        address tokenIn;
        bool zeroForOne; // token0 < token1
    }
    mapping(address => routeInfo[]) public routeForToken;

    event Reinvest(address indexed caller, uint bounty, uint fee, uint amount);
    event RewardAdded(address reward);
    event RewardRemoved(address reward);
    event EmergencyWithdrawn(address indexed to, uint amount);

    constructor(address _admin, address _timelock, address _setter) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(SETTER_ROLE, _setter);
        _grantRole(TIMELOCK_ROLE, _timelock);
        _setRoleAdmin(TIMELOCK_ROLE, TIMELOCK_ROLE);

        platformFeeReceiver = _admin;
        address[] memory _rewards = INeadStake(neadStake).rewardsList();
        rewards = _rewards;
        treasuryFee = 10;
        IERC20(asset).approve(neadStake, type(uint).max);
    }

    function initialize(address _vault) external initializer {
        vault = _vault;
        IERC20(asset).approve(_vault, type(uint).max);
    }

    function ramsesV2SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        (address pool, address tokenIn) = abi.decode(data, (address, address));
        require(msg.sender == pool, "!pool");

        if (amount0Delta > 0) {
            IERC20(tokenIn).transfer(msg.sender, uint256(amount0Delta));
        } else {
            IERC20(tokenIn).transfer(msg.sender, uint256(amount1Delta));
        }
    }

    function registerStake(uint amount) external {
        require(msg.sender == vault, "!vault");
        INeadStake(neadStake).deposit(amount);
    }

    function unregisterStake(uint amount) external {
        require(msg.sender == vault, "!vault");
        INeadStake(neadStake).withdraw(amount);
    }

    function reinvest(address to) external {
        INeadStake(neadStake).getReward();
        address[] memory _rewards = rewards;
        uint len = _rewards.length;
        uint amount;

        unchecked {
            for (uint i; i < len; ++i) {
                uint bal = IERC20(_rewards[i]).balanceOf(address(this));
                if (_rewards[i] == asset) {
                    amount += bal;
                } else if (_rewards[i] == xRam) {
                    uint id = IXRam(xRam).xRamConvertToNft(bal);
                    uint amountBefore = IERC20(asset).balanceOf(address(this));
                    IVotingEscrow(votingEscrow).safeTransferFrom(
                        address(this),
                        asset,
                        id
                    );
                    amount +=
                        IERC20(asset).balanceOf(address(this)) -
                        amountBefore;
                } else {
                    amount += _swap(_rewards[i], bal);
                }
            }
        }

        // calculate fees
        // shit never under/overflows, would also revert if ever...
        uint treasury;
        uint harvest;
        unchecked {
            treasury = (amount * treasuryFee) / basis;
            harvest = (amount * harvestFee) / basis;
        }

        if (treasury > 0) {
            IERC20(asset).transfer(platformFeeReceiver, treasury);
        }

        if (harvest > 0) {
            IERC20(asset).transfer(to, harvest);
        }

        unchecked {
            amount -= (treasury + harvest);
        }

        INeadStake(neadStake).deposit(amount);
        emit Reinvest(msg.sender, harvest, treasury, amount);
    }

    function _swap(
        address token,
        uint amountIn
    ) internal returns (uint amountOut) {
        routeInfo[] memory _routes = routeForToken[token];
        uint len = _routes.length;

        int amount = int(amountIn);
        for (uint i; i < len; ) {
            if (_routes[i].zeroForOne) {
                (, amount) = IRamsesV2Pool(_routes[i].pool).swap(
                    address(this),
                    _routes[i].zeroForOne,
                    amount < 0 ? -amount : amount,
                    MIN_SQRT_RATIO + 1,
                    abi.encode(_routes[i].pool, _routes[i].tokenIn)
                );
            } else {
                (amount, ) = IRamsesV2Pool(_routes[i].pool).swap(
                    address(this),
                    _routes[i].zeroForOne,
                    amount < 0 ? -amount : amount,
                    MAX_SQRT_RATIO - 1,
                    abi.encode(_routes[i].pool, _routes[i].tokenIn)
                );
            }
            unchecked {
                ++i;
            }
        }
        amountOut = uint(-amount);
    }

    function setFees(
        uint _treasuryFee,
        uint _harvestFee
    ) external onlyRole(SETTER_ROLE) {
        treasuryFee = _treasuryFee;
        harvestFee = _harvestFee;
    }

    function setFeeReceiver(address receiver) external onlyRole(SETTER_ROLE) {
        platformFeeReceiver = receiver;
    }

    function getTotalStaked() external view returns (uint total) {
        total = INeadStake(neadStake).balanceOf(address(this));
    }

    function rewardsList() external view returns (address[] memory _rewards) {
        _rewards = rewards;
    }

    /// @notice manually claims rewards from neadStake and sends to msg.sender. Not expected to be called on a regular basis but leaving as a contingency
    function manualClaimRewards(address token) external onlyRole(SETTER_ROLE) {
        INeadStake(neadStake).getReward(); // neadStake getReward claims all tokens
        if (token != address(0)) {
            // any remaining tokens in the contract will be reinvested in the next reinvest() call
            uint bal = IERC20(token).balanceOf(address(this));
            IERC20(token).transfer(msg.sender, bal);
        } else {
            address[] memory _rewards = rewards;
            uint len = _rewards.length;
            for (uint i; i < len; ++i) {
                uint bal = IERC20(_rewards[i]).balanceOf(address(this));
                if (bal > 0) {
                    IERC20(token).transfer(msg.sender, bal);
                }
            }
        }
    }

    function addReward(
        address token,
        routeInfo[] calldata _routes
    ) external onlyRole(SETTER_ROLE) {
        rewards.push(token);
        for (uint i; i < _routes.length; ++i) {
            routeForToken[token].push(_routes[i]);
        }
        emit RewardAdded(token);
    }

    function setRoute(
        address token,
        routeInfo[] calldata _routes
    ) external onlyRole(SETTER_ROLE) {
        delete routeForToken[token];
        for (uint i; i < _routes.length; ++i) {
            routeForToken[token].push(_routes[i]);
        }
    }

    function removeReward(address token) external onlyRole(SETTER_ROLE) {
        address[] memory _rewards = rewards;
        uint len = _rewards.length;
        uint idx;

        // get reward token index
        for (uint i; i < len; ++i) {
            if (_rewards[i] == token) {
                idx = i;
            }
        }

        // remove from rewards list
        for (uint256 i = idx; i < len - 1; ++i) {
            rewards[i] = rewards[i + 1];
        }
        rewards.pop();
        delete routeForToken[token];
        emit RewardRemoved(token);
    }

    /// @notice withdraws the entire balance of the strategy and sends to `_to`, contingency measure just in case something goes wrong. Function is timelocked.
    function emergencyWithdraw(
        address _to,
        uint amount
    ) external onlyRole(TIMELOCK_ROLE) {
        INeadStake(neadStake).withdraw(amount);
        IERC20(asset).transfer(_to, amount);
        emit EmergencyWithdrawn(_to, amount);
    }
}

