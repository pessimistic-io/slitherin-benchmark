// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ERC20Upgradeable.sol";
import "./ERC20_IERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";

import "./EnneadWhitelist.sol";
import "./IPair.sol";
import "./IRamsesV2Pool.sol";

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
        uint256 amount; // amount of xRAM
        uint256 start; // start unix timestamp
        uint256 maxEnd; // start + maxVest (end timestamp)
        uint256 vestID; // vest identifier (starting from 0)
    }

    mapping(address user => VestPosition[]) public vestInfo;

    // Partner/Modular whitelists, at the end of the storage slots in case of more partners
    EnneadWhitelist public enneadWhitelist;

    /// V1.1 swap logic

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

    // Events
    event WhitelistStatus(address indexed candidate, bool status);

    event RamConverted(address indexed user, uint256);
    event XRamRedeemed(address indexed user, uint256);

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
        require(msg.sender == timelock, "xRAM: !Auth");
        _;
    }

    modifier onlyWhitelistOperator() {
        require(
            msg.sender == whitelistOperator,
            "xRAM: Only the whitelisting operator can call this function"
        );
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
    ) internal override {
        if (to != address(0)) {
            require(
                syncAndCheckIsWhitelisted(from),
                "xRAM: You are not able to transfer this token"
            );
        }
    }

    /*****************************************************************/
    // General use functions
    /*****************************************************************/

    ///@dev mints xRAM for each RAM.
    function convertRam(uint256 _amount) external {
        // restricted to whitelisted contracts
        // to prevent users from minting xRAM and can't convert back without penalty
        require(syncAndCheckIsWhitelisted(msg.sender), "xRAM: !auth");
        require(_amount > 0, "xRAM: Amount must be greater than 0");
        ram.transferFrom(msg.sender, address(this), _amount);
        _mint(msg.sender, _amount);
        emit RamConverted(msg.sender, _amount);
    }

    ///@dev convert xRAM to veRAM at veExitRatio (new veNFT form)
    function xRamConvertToNft(
        uint256 _amount
    ) external returns (uint256 veRamTokenId) {
        require(_amount > 0, "xRAM: Amount must be greater than 0");
        _burn(msg.sender, _amount);
        uint256 _adjustedAmount = ((veExitRatio * _amount) / PRECISION);
        _mint(multisig, (_amount - _adjustedAmount));
        veRamTokenId = veRam.create_lock_for(
            _adjustedAmount,
            MAXTIME,
            msg.sender
        );
        emit XRamRedeemed(msg.sender, _amount);
        return veRamTokenId;
    }

    ///@dev convert xRAM to veRAM at a 1:1 ratio (increase existing veNFT)
    function xRamIncreaseNft(uint256 _amount, uint256 _tokenID) external {
        require(_amount > 0, "xRAM: Amount must be greater than 0");
        _burn(msg.sender, _amount);

        IVeRam _veRam = veRam;

        // ensure the msg.sender is approved to modify the veRam
        require(
            _veRam.isApprovedOrOwner(msg.sender, _tokenID),
            "xRAM: You are not approved to extend this veRAM position"
        );

        // ensure the xRAM contract is approved to increase the amount of this veRAM
        // this is to ensure extending lock time will work
        require(
            _veRam.isApprovedOrOwner(address(this), _tokenID),
            "xRAM: The contract has not been given approval to your veRAM position"
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
                "xRAM: veRAM isn't max locked"
            );
        }

        veRam.increase_amount(_tokenID, _adjustedAmount);
        emit XRamRedeemed(msg.sender, _amount);
    }

    ///@dev exit instantly with a penalty
    function instantExit(uint256 _amount) external {
        require(_amount > 0, "xRAM: Amount must be greater than 0");
        uint256 exitAmount = ((exitRatio * _amount) / PRECISION);
        uint256 haircut = _amount - exitAmount;

        _burn(msg.sender, _amount);

        if (swapEnabled) {
            haircut = haircut / 2;
            // swap and transfer half to multisig
            uint256 amountOut = _swap(haircut);
            IERC20Upgradeable(swapTo).transfer(multisig, amountOut);
            // mint half to multisig
            _mint(multisig, haircut);
        } else {
            // mint the exit penalty to the multisig
            _mint(multisig, haircut);
        }

        ram.transfer(msg.sender, exitAmount);
        emit InstantExit(msg.sender, _amount);
    }

    ///@dev vesting xRAM --> RAM functionality
    function createVest(uint256 _amount) external {
        require(_amount > 0, "xRAM: Amount must be greater than 0");
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
    function exitVest(uint256 _vestID, bool _ve) external returns (bool) {
        uint256 vestCount = vestInfo[msg.sender].length;
        require(
            vestCount != 0 && _vestID <= vestCount - 1,
            "xRAM: Vest does not exist"
        );
        VestPosition storage _vest = vestInfo[msg.sender][_vestID];
        require(
            _vest.amount != 0 && _vest.vestID == _vestID,
            "xRAM: Vest not active"
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
        require(msg.sender == multisig, "xRAM: !Auth");
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

    ///@notice allows the whitelist operator to add an address to the xRAM whitelist
    function addWhitelist(address _whitelistee) external onlyWhitelistOperator {
        _updateWhitelist(_whitelistee, true);
    }

    ///@notice allows the whitelist operator to remove an address from the xRAM whitelist
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

    function setSwapEnabled(bool isEnabled) external {
        require(msg.sender == multisig, "!msig");
        swapEnabled = isEnabled;
    }

    function setRoute(routeInfo[] calldata _routes) external {
        require(msg.sender == multisig, "!msig");
        delete route;
        uint256 len = _routes.length;
        for (uint256 i; i < len; ++i) {
            route.push(_routes[i]);
        }
        swapTo = _routes[len - 1].zeroForOne
            ? IRamsesV2Pool(_routes[len - 1].pool).token1()
            : IRamsesV2Pool(_routes[len - 1].pool).token0();
    }

    /*****************************************************************/
    // Getter functions
    /*****************************************************************/

    ///@dev return the amount of RAM within the contract
    function getBalanceResiding() public view returns (uint256) {
        return ram.balanceOf(address(this));
    }

    /// @notice Potentially writes new whitelsited pools to storage then return if an address is whitelisted to transfer xRAM
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

    /*****************************************************************/
    // swap logic
    /*****************************************************************/

    function ramsesV2SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        (address pool, address tokenIn) = abi.decode(data, (address, address));
        require(msg.sender == pool, "!pool");

        if (amount0Delta > 0) {
            IERC20Upgradeable(tokenIn).transfer(
                msg.sender,
                uint256(amount0Delta)
            );
        } else {
            IERC20Upgradeable(tokenIn).transfer(
                msg.sender,
                uint256(amount1Delta)
            );
        }
    }

    function _swap(uint256 amountIn) internal returns (uint256 amountOut) {
        routeInfo[] memory _routes = route;
        uint256 len = _routes.length;

        int256 amount = int256(amountIn);
        for (uint256 i; i < len; ) {
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
        amountOut = uint256(-amount);
    }
}

