// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ERC20Upgradeable.sol";
import "./ERC20_IERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Math.sol";

import "./EnneadWhitelist.sol";
import "./IPair.sol";
import "./IRamsesV2Pool.sol";

library TickMath {
    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;

    function getSqrtRatioAtTick(
        int24 tick
    ) internal pure returns (uint160 sqrtPriceX96) {
        uint256 absTick = tick < 0
            ? uint256(-int256(tick))
            : uint256(int256(tick));
        require(absTick <= uint256(uint24(MAX_TICK)), "T");

        uint256 ratio = absTick & 0x1 != 0
            ? 0xfffcb933bd6fad37aa2d162d1a594001
            : 0x100000000000000000000000000000000;
        if (absTick & 0x2 != 0)
            ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
        if (absTick & 0x4 != 0)
            ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
        if (absTick & 0x8 != 0)
            ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
        if (absTick & 0x10 != 0)
            ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
        if (absTick & 0x20 != 0)
            ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
        if (absTick & 0x40 != 0)
            ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
        if (absTick & 0x80 != 0)
            ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
        if (absTick & 0x100 != 0)
            ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
        if (absTick & 0x200 != 0)
            ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
        if (absTick & 0x400 != 0)
            ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
        if (absTick & 0x800 != 0)
            ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
        if (absTick & 0x1000 != 0)
            ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
        if (absTick & 0x2000 != 0)
            ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
        if (absTick & 0x4000 != 0)
            ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
        if (absTick & 0x8000 != 0)
            ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
        if (absTick & 0x10000 != 0)
            ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
        if (absTick & 0x20000 != 0)
            ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
        if (absTick & 0x40000 != 0)
            ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
        if (absTick & 0x80000 != 0)
            ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;

        if (tick > 0) ratio = type(uint256).max / ratio;

        sqrtPriceX96 = uint160(
            (ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1)
        );
    }
}

interface IVeRam {
    struct LockedBalance {
        int128 amount;
        uint256 end;
    }

    function isApprovedOrOwner(
        address _spender,
        uint256 _tokenID
    ) external view returns (bool);

    function create_lock_for(
        uint256 _amount,
        uint256 _length,
        address _for
    ) external returns (uint256);

    function increase_amount(uint256 _tokenID, uint256 _amount) external;

    function increase_unlock_time(uint256 _tokenID, uint256 _length) external;

    function locked(
        uint256 _tokenId
    ) external view returns (LockedBalance memory);
}

interface IVoter {
    function isGauge(address _gauge) external view returns (bool);
}

contract XRam is Initializable, ERC20Upgradeable {
    // constants and immutables
    uint256 public constant PRECISION = 100;
    uint256 public constant MAXTIME = 4 * 365 days;
    IERC20Upgradeable public immutable ram;
    IVeRam public immutable veRam;
    IVoter public immutable voter;

    // addresses
    address public timelock;
    address public multisig;
    address public whitelistOperator;

    mapping(address => bool) public isWhitelisted;

    ///@dev ratio of earned ram via exit penalty. 65% means they earn 65% of the RAM value
    uint256 public exitRatio = 65; // 65%
    uint256 public veExitRatio = 80; // 80%
    uint256 public minVest = 7 days; /// @notice the initial minimum vesting period is 7 days (one week)
    uint256 public veMaxVest = 30 days; /// @notice the initial maximum vesting period for vote escrowed exits is 30 days (1 month)
    uint256 public maxVest = 90 days; /// @notice the initial maximum vesting period is 90 days (3 months)

    struct VestPosition {
        uint256 amount; // amount of xoRAM
        uint256 start; // start unix timestamp
        uint256 maxEnd; // start + maxVest (end timestamp)
        uint256 vestID; // vest identifier (starting from 0)
    }

    mapping(address user => VestPosition[]) public vestInfo;

    // Partner/Modular whitelists, at the end of the storage slots in case of more partners
    EnneadWhitelist public enneadWhitelist;

    /// V1.1 swap logic - deprecated

    // Mirrored from TickMath
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO =
        1461446703485210103287273052203988822378723970342;

    struct routeInfo {
        address pool;
        address tokenIn;
        bool zeroForOne; // token0 < token1
    }

    routeInfo[] public route;
    address public swapTo;
    bool public swapEnabled;

    /// V1.2 twaps
    address public _pool;
    uint32 public duration;
    bool public optionEnabled;
    address public weth; // can be any other token really

    bool public paused;

    // Events
    event WhitelistStatus(address indexed candidate, bool status);

    event RamConverted(address indexed user, uint256);
    event XoRamRedeemed(address indexed user, uint256);

    event NewExitRatios(uint256 exitRatio, uint256 veExitRatio);
    event NewVestingTimes(uint256 min, uint256 max, uint256 veMaxVest);
    event InstantExit(address indexed user, uint256);

    event NewVest(
        address indexed user,
        uint256 indexed vestId,
        uint256 indexed amount
    );
    event ExitVesting(
        address indexed user,
        uint256 indexed vestId,
        uint256 amount
    );
    event CancelVesting(
        address indexed user,
        uint256 indexed vestId,
        uint256 amount
    );

    modifier onlyTimelock() {
        require(msg.sender == timelock, "xoRAM: !Auth");
        _;
    }

    modifier onlyWhitelistOperator() {
        require(
            msg.sender == whitelistOperator,
            "xoRAM: Only the whitelisting operator can call this function"
        );
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "xoRAM: paused");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address _ramToken,
        address _veRam,
        address _voter
    ) initializer() {
        ram = IERC20Upgradeable(_ramToken);
        veRam = IVeRam(_veRam);
        voter = IVoter(_voter);
    }

    function initialize(
        address _timelock,
        address _multisig,
        address _whitelistOperator,
        address _enneadWhitelist
    ) external initializer {
        __ERC20_init_unchained("Extended RAM", "xRAM");
        // set addresses
        timelock = _timelock;
        multisig = _multisig;
        whitelistOperator = _whitelistOperator;
        enneadWhitelist = EnneadWhitelist(_enneadWhitelist);

        // set initial parameters
        exitRatio = 65; // 65%
        veExitRatio = 80; // 80%
        minVest = 7 days; /// @notice the initial minimum vesting period is 7 days (one week)
        veMaxVest = 30 days; /// @notice the initial maximum vesting period for vote escrowed exits is 30 days (1 month)
        maxVest = 90 days; /// @notice the initial maximum vesting period is 90 days (3 months)

        // approve ram to veRam
        ram.approve(address(veRam), type(uint256).max);

        // whitelist address(0), for minting
        _updateWhitelist(address(0), true);

        // whitelist self, voter, and multisig
        _updateWhitelist(address(this), true);
        _updateWhitelist(address(voter), true);
        _updateWhitelist(multisig, true);

        // whitelist ennead
        _updateWhitelist(0x1863736c768f232189F95428b5ed9A51B0eCcAe5, true); // Ennead LP Depositor
        _updateWhitelist(0xe99ead648Fb2893d1CFA4e8Fe8B67B35572d2581, true); // Ennead NFP Depositor
        _updateWhitelist(0x7D07A61b8c18cb614B99aF7B90cBBc8cD8C72680, true); // neadStake
    }

    /*****************************************************************/
    // ERC20 Overrides
    /*****************************************************************/

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 //amount
    ) internal override whenNotPaused {
        if (to != address(0)) {
            require(
                syncAndCheckIsWhitelisted(from),
                "xoRAM: You are not able to transfer this token"
            );
        }
    }

    /*****************************************************************/
    // General use functions
    /*****************************************************************/

    ///@dev mints xoRAM for each RAM.
    function convertRam(uint256 _amount) external whenNotPaused {
        // restricted to whitelisted contracts
        // to prevent users from minting xoRAM and can't convert back without penalty
        require(syncAndCheckIsWhitelisted(msg.sender), "xoRAM: !auth");
        require(_amount > 0, "xoRAM: Amount must be greater than 0");
        ram.transferFrom(msg.sender, address(this), _amount);
        _mint(msg.sender, _amount);
        emit RamConverted(msg.sender, _amount);
    }

    ///@dev convert xoRAM to veRAM at veExitRatio (new veNFT form)
    function xRamConvertToNft(
        uint256 _amount
    ) external whenNotPaused returns (uint256 veRamTokenId) {
        require(_amount > 0, "xoRAM: Amount must be greater than 0");
        _burn(msg.sender, _amount);
        uint256 _adjustedAmount = ((veExitRatio * _amount) / PRECISION);
        _mint(multisig, (_amount - _adjustedAmount));
        veRamTokenId = veRam.create_lock_for(
            _adjustedAmount,
            MAXTIME,
            msg.sender
        );
        emit XoRamRedeemed(msg.sender, _amount);
        return veRamTokenId;
    }

    ///@dev convert xoRAM to veRAM (increase existing veNFT)
    function xRamIncreaseNft(
        uint256 _amount,
        uint256 _tokenID
    ) external whenNotPaused {
        require(_amount > 0, "xoRAM: Amount must be greater than 0");
        _burn(msg.sender, _amount);

        IVeRam _veRam = veRam;

        // ensure the msg.sender is approved to modify the veRam
        require(
            _veRam.isApprovedOrOwner(msg.sender, _tokenID),
            "xoRAM: You are not approved to extend this veRAM position"
        );

        // ensure the xoRAM contract is approved to increase the amount of this veRAM
        // this is to ensure extending lock time will work
        require(
            _veRam.isApprovedOrOwner(address(this), _tokenID),
            "xoRAM: The contract has not been given approval to your veRAM position"
        );

        uint256 _adjustedAmount = ((veExitRatio * _amount) / PRECISION);

        // mint the exit penalty to the multisig
        _mint(multisig, (_amount - _adjustedAmount));

        // ensures that the veRAM is 4 year locked
        try _veRam.increase_unlock_time(_tokenID, MAXTIME) {} catch {
            // check if lock duration is already max if the call fails
            // redundant, but just in case
            IVeRam.LockedBalance memory locked = _veRam.locked(_tokenID);
            require(
                locked.end >= ((block.timestamp + MAXTIME) / 1 weeks) * 1 weeks,
                "xoRAM: veRAM isn't max locked"
            );
        }

        veRam.increase_amount(_tokenID, _adjustedAmount);
        emit XoRamRedeemed(msg.sender, _amount);
    }

    /**
     * @dev exit instantly with a penalty
     * @param _amount amount of xoRAM to exit
     * @param maxPayAmount maximum amount of eth user is willing to pay
     */
    function instantExit(
        uint256 _amount,
        uint256 maxPayAmount
    ) external whenNotPaused {
        require(_amount > 0, "xoRAM: Amount must be greater than 0");
        uint256 exitAmount = ((exitRatio * _amount) / PRECISION);

        _burn(msg.sender, _amount);

        if (optionEnabled) {
            uint256 amountToPay = (_amount * (100 - exitRatio)) / 100;
            amountToPay = quotePrice(amountToPay);
            require(amountToPay <= maxPayAmount, "Slippage!");

            IERC20Upgradeable(weth).transferFrom(
                msg.sender,
                multisig,
                amountToPay
            );
        } else {
            // mint the exit penalty to the multisig
            uint256 haircut = _amount - exitAmount;
            _mint(multisig, haircut);
        }

        ram.transfer(msg.sender, exitAmount);
        emit InstantExit(msg.sender, _amount);
    }

    ///@dev vesting xRAM --> RAM functionality
    function createVest(uint256 _amount) external whenNotPaused {
        require(_amount > 0, "xoRAM: Amount must be greater than 0");
        _burn(msg.sender, _amount);
        uint256 vestLength = vestInfo[msg.sender].length;
        vestInfo[msg.sender].push(
            VestPosition(
                _amount,
                block.timestamp,
                block.timestamp + maxVest,
                vestLength
            )
        );
        emit NewVest(msg.sender, vestLength, _amount);
    }

    ///@dev handles all situations regarding exiting vests
    function exitVest(
        uint256 _vestID,
        bool _ve
    ) external whenNotPaused returns (bool) {
        uint256 vestCount = vestInfo[msg.sender].length;
        require(
            vestCount != 0 && _vestID <= vestCount - 1,
            "xoRAM: Vest does not exist"
        );
        VestPosition storage _vest = vestInfo[msg.sender][_vestID];
        require(
            _vest.amount != 0 && _vest.vestID == _vestID,
            "xoRAM: Vest not active"
        );
        uint256 _amount = _vest.amount;
        uint256 _start = _vest.start;
        _vest.amount = 0;

        // case: vest has not crossed the minimum vesting threshold
        if (block.timestamp < _start + minVest) {
            _mint(msg.sender, _amount);
            emit CancelVesting(msg.sender, _vestID, _amount);
            return true;
        }

        ///@dev if it is not a veRAM exit
        if (!_ve) {
            // case: vest is complete
            if (_vest.maxEnd <= block.timestamp) {
                ram.transfer(msg.sender, _amount);
                emit ExitVesting(msg.sender, _vestID, _amount);
                return true;
            }
            // case: vest is in progress
            else {
                uint256 base = (_amount * exitRatio) / PRECISION;
                uint256 vestEarned = ((_amount *
                    (PRECISION - exitRatio) *
                    (block.timestamp - _start)) / maxVest) / PRECISION;

                uint256 exitedAmount = base + vestEarned;

                _mint(multisig, (_amount - exitedAmount));
                ram.transfer(msg.sender, exitedAmount);
                emit ExitVesting(msg.sender, _vestID, _amount);
                return true;
            }
        }
        // exit to veRam
        else {
            uint256 veMaxEnd = _start + veMaxVest;
            // case: vest is complete for vote escrow threshold
            if (veMaxEnd <= block.timestamp) {
                veRam.create_lock_for(_amount, MAXTIME, msg.sender);
                emit ExitVesting(msg.sender, _vestID, _amount);
                return true;
            }
            // case: vest is in progress for vote escrow exit
            else {
                uint256 base = (_amount * veExitRatio) / PRECISION;
                uint256 vestEarned = ((_amount *
                    (PRECISION - veExitRatio) *
                    (block.timestamp - _start)) / veMaxVest) / PRECISION;

                uint256 exitedAmount = base + vestEarned;

                _mint(multisig, (_amount - exitedAmount));
                veRam.create_lock_for(exitedAmount, MAXTIME, msg.sender);
                emit ExitVesting(msg.sender, _vestID, _amount);
                return true;
            }
        }
    }

    /*****************************************************************/
    // Permissioned functions, timelock/operator gated
    /*****************************************************************/

    ///@dev allows the multisig to redeem collected xRAM
    function multisigRedeem(uint256 _amount) external {
        require(msg.sender == multisig, "xoRAM: !Auth");
        _burn(msg.sender, _amount);

        ram.transferFrom(address(this), msg.sender, _amount);
    }

    ///@dev timelock only: alter the parameters for exiting
    function alterExitRatios(
        uint256 _newExitRatio,
        uint256 _newVeExitRatio
    ) external onlyTimelock {
        exitRatio = _newExitRatio;
        veExitRatio = _newVeExitRatio;
        emit NewExitRatios(_newExitRatio, _newVeExitRatio);
    }

    ///@dev allows the timelock to rescue any trapped tokens
    function rescueTrappedTokens(
        address[] calldata _tokens,
        uint256[] calldata _amounts
    ) external onlyTimelock {
        for (uint256 i = 0; i < _tokens.length; ++i) {
            IERC20Upgradeable(_tokens[i]).transfer(multisig, _amounts[i]);
        }
    }

    ///@dev change the minimum and maximum vest durations
    function reinitializeVestingParameters(
        uint256 _min,
        uint256 _max,
        uint256 _veMax
    ) external onlyTimelock {
        (minVest, maxVest, veMaxVest) = (_min, _max, _veMax);

        emit NewVestingTimes(_min, _max, _veMax);
    }

    ///@dev change minimum vesting parameter
    function changeMinimumVestingLength(
        uint256 _minVest
    ) external onlyTimelock {
        minVest = _minVest;

        emit NewVestingTimes(_minVest, maxVest, veMaxVest);
    }

    ///@dev change maximum vesting parameter
    function changeMaximumVestingLength(
        uint256 _maxVest
    ) external onlyTimelock {
        maxVest = _maxVest;

        emit NewVestingTimes(minVest, _maxVest, veMaxVest);
    }

    ///@dev change vote escrow maximum vesting parameter
    function changeVeMaximumVestingLength(
        uint256 _veMax
    ) external onlyTimelock {
        veMaxVest = _veMax;

        emit NewVestingTimes(minVest, maxVest, _veMax);
    }

    ///@dev migrates the timelock to another contract
    function migrateTimelock(address _timelock) external onlyTimelock {
        timelock = _timelock;
    }

    ///@dev migrates the multisig to another contract
    function migrateMultisig(address _multisig) external onlyTimelock {
        multisig = _multisig;
    }

    ///@dev migrates The Ennead whitelist
    function migrateEnneadWhitelist(
        address _enneadWhitelist
    ) external onlyWhitelistOperator {
        enneadWhitelist = EnneadWhitelist(_enneadWhitelist);
    }

    ///@dev only callable by the whitelistOperator contract
    function adjustWhitelist(
        address[] calldata _candidates,
        bool[] calldata _status
    ) external onlyWhitelistOperator {
        for (uint256 i = 0; i < _candidates.length; ++i) {
            _updateWhitelist(_candidates[i], _status[i]);
        }
    }

    ///@notice allows the whitelist operator to add an address to the xoRAM whitelist
    function addWhitelist(address _whitelistee) external onlyWhitelistOperator {
        _updateWhitelist(_whitelistee, true);
    }

    ///@notice allows the whitelist operator to remove an address from the xoRAM whitelist
    function removeWhitelist(
        address _whitelistee
    ) external onlyWhitelistOperator {
        _updateWhitelist(_whitelistee, false);
    }

    function _updateWhitelist(address _whitelistee, bool _status) internal {
        isWhitelisted[_whitelistee] = _status;

        emit WhitelistStatus(_whitelistee, _status);
    }

    ///@dev timelock can change the operator contract
    function changeWhitelistOperator(
        address _newOperator
    ) external onlyTimelock {
        whitelistOperator = _newOperator;
    }

    function setOptionsEnabled(bool isEnabled) external {
        require(msg.sender == multisig, "!msig");

        if (isEnabled && swapEnabled) {
            swapEnabled = false;
        }

        optionEnabled = isEnabled;
    }

    function setPool(address newPool) external {
        require(msg.sender == multisig, "!msig");

        _pool = newPool;
    }

    /// @notice set twap interval, 3600 for 1 hour twap
    function setSecondsAgo(uint32 _duration) external {
        require(msg.sender == multisig, "!msig");

        duration = _duration;
    }

    function setWeth(address _weth) external {
        require(msg.sender == multisig, "!msig");
        weth = _weth;
    }

    function setPaused(bool _paused) external {
        require(msg.sender == multisig, "!msig");
        paused = _paused;
    }

    /*****************************************************************/
    // Getter functions
    /*****************************************************************/

    ///@dev return the amount of RAM within the contract
    function getBalanceResiding() public view returns (uint256) {
        return ram.balanceOf(address(this));
    }

    /// @notice Potentially writes new whitelsited pools to storage then return if an address is whitelisted to transfer xoRAM
    /// @param _address The address of the sender
    function syncAndCheckIsWhitelisted(address _address) public returns (bool) {
        if (isWhitelisted[_address]) {
            return true;
        }

        // automatically whitelist gauges
        if (voter.isGauge(_address)) {
            _updateWhitelist(_address, true);
            return true;
        }

        // automatically whitelist ennead addresses
        if (enneadWhitelist.syncAndCheckIsWhitelisted(_address)) {
            _updateWhitelist(_address, true);
            return true;
        }

        return false;
    }

    ///@dev returns the total number of individual vests the user has
    function usersTotalVests(address _user) public view returns (uint256) {
        return vestInfo[_user].length;
    }

    function quotePayment(
        uint256 amount
    ) public view returns (uint256 payAmount) {
        uint256 amountToPay = (amount * (100 - exitRatio)) / 100;
        payAmount = quotePrice(amountToPay);
    }

    function quotePrice(
        uint256 amountIn
    ) public view returns (uint256 amountOut) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = duration;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives, , ) = IRamsesV2Pool(_pool).observe(
            secondsAgos
        );

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        int24 arithmeticMeanTick = int24(
            tickCumulativesDelta / int56(int32(duration))
        );
        if (
            tickCumulativesDelta < 0 &&
            (tickCumulativesDelta % int56(int32(duration)) != 0)
        ) arithmeticMeanTick--;

        int24 tick = int24(tickCumulativesDelta / int56(int32(duration)));
        if (
            tickCumulativesDelta < 0 &&
            (tickCumulativesDelta % int56(int32(duration)) != 0)
        ) {
            tick--;
        }

        // hardcoded zeroForOne
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            amountOut = Math.mulDiv(1 << 192, amountIn, ratioX192);
        } else {
            uint256 ratioX128 = Math.mulDiv(
                sqrtRatioX96,
                sqrtRatioX96,
                1 << 64
            );
            amountOut = Math.mulDiv(1 << 128, amountIn, ratioX128);
        }
    }

    /*****************************************************************/
    // overrides
    /*****************************************************************/

    function name() public pure override returns (string memory) {
        return "Extended Options RAM";
    }

    function symbol() public pure override returns (string memory) {
        return "xoRAM";
    }
}

