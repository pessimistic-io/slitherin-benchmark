// SPDX-License-Identifier: BUSL1.1

pragma solidity ^0.8.0;

import "./AggregatorV3Interface.sol";
import "./ISwapper.sol";
import "./UniV2Mixin.sol";
import "./BalMixin.sol";
import "./VeloSolidMixin.sol";
import "./UniV3Mixin.sol";
import "./ReaperAccessControl.sol";
import "./ReaperMathUtils.sol";
import "./AccessControlEnumerableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";

contract ReaperSwapper is
    UniV2Mixin,
    BalMixin,
    VeloSolidMixin,
    UniV3Mixin,
    ReaperAccessControl,
    UUPSUpgradeable,
    AccessControlEnumerableUpgradeable
{
    using ReaperMathUtils for uint256;
    using SafeERC20Upgradeable for IERC20MetadataUpgradeable;

    struct ChainlinkResponse {
        uint80 roundId;
        int256 answer;
        uint256 timestamp;
        bool success;
        uint8 decimals;
    }

    // timeout is maximum time period allowed since Chainlink's latest round data timestamp,
    // beyond which Chainlink is considered frozen.
    struct CLAggregatorData {
        AggregatorV3Interface aggregator;
        uint256 timeout; // this allows us to use different timeouts per asset/aggregator
    }

    /**
     * Reaper Roles in increasing order of privilege.
     * {STRATEGIST} - Role conferred to authors of strategies, allows for setting swap paths.
     * {GUARDIAN} - Multisig requiring 2 signatures for setting quoters and CL aggregator addresses.
     *
     * The DEFAULT_ADMIN_ROLE (in-built access control role) will be granted to a multisig requiring 4
     * signatures. This role would have upgrading capability, as well as the ability to grant any other
     * roles.
     *
     * Note that roles are cascading. So any higher privileged role should be able to perform all the functions
     * of any lower privileged role.
     */
    bytes32 public constant STRATEGIST = keccak256("STRATEGIST");
    bytes32 public constant GUARDIAN = keccak256("GUARDIAN");

    // Use to convert a price answer to an 18-digit precision uint
    uint256 public constant TARGET_DIGITS = 18;
    // Use to calculate slippage when using CL aggregator for minAmountOut
    uint256 public constant PERCENT_DIVISOR = 10_000;

    uint256 public constant UPGRADE_TIMELOCK = 48 hours; // minimum 48 hours for RF
    uint256 public constant FUTURE_NEXT_PROPOSAL_TIME = 365 days * 100;
    uint256 public upgradeProposalTime;

    // token => CL aggregator data mapping
    mapping(address => CLAggregatorData) public aggregatorData;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize(address[] memory _strategists, address _guardian, address _superAdmin) public initializer {
        __UUPSUpgradeable_init();
        __AccessControlEnumerable_init();

        uint256 numStrategists = _strategists.length;
        for (uint256 i = 0; i < numStrategists; i = i.uncheckedInc()) {
            _grantRole(STRATEGIST, _strategists[i]);
        }
        _grantRole(GUARDIAN, _guardian);
        _grantRole(DEFAULT_ADMIN_ROLE, _superAdmin);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        clearUpgradeCooldown();
    }

    function updateUniV2SwapPath(address _tokenIn, address _tokenOut, address _router, address[] calldata _path)
        external
        override
    {
        _atLeastRole(STRATEGIST);
        _updateVeloSwapPath(_tokenIn, _tokenOut, _router, _path);
    }

    function updateBalSwapPoolID(address _tokenIn, address _tokenOut, address _vault, bytes32 _poolID)
        external
        override
    {
        _atLeastRole(STRATEGIST);
        _updateBalSwapPoolID(_tokenIn, _tokenOut, _vault, _poolID);
    }

    function updateVeloSwapPath(address _tokenIn, address _tokenOut, address _router, address[] calldata _path)
        external
        override
    {
        _atLeastRole(STRATEGIST);
        _updateVeloSwapPath(_tokenIn, _tokenOut, _router, _path);
    }

    function updateUniV3SwapPath(address _tokenIn, address _tokenOut, address _router, address[] calldata _path)
        external
        override
    {
        _atLeastRole(STRATEGIST);
        _updateUniV3SwapPath(_tokenIn, _tokenOut, _router, _path);
    }

    function updateUniV3Quoter(address _router, address _quoter) external override {
        _atLeastRole(GUARDIAN);
        _updateUniV3Quoter(_router, _quoter);
    }

    function updateTokenAggregator(address _token, address _aggregator, uint256 _timeout) external {
        _atLeastRole(GUARDIAN);
        aggregatorData[_token] = CLAggregatorData(AggregatorV3Interface(_aggregator), _timeout);
        _getChainlinkPriceTargetDigits(_token);
    }

    function swapUniV2(
        address _from,
        address _to,
        uint256 _amount,
        MinAmountOutData memory _minAmountOutData,
        address _router
    ) external pullFromBefore(_from, _amount) pushFromAndToAfter(_from, _to) returns (uint256) {
        uint256 minAmountOut = _calculateMinAmountOut(_from, _to, _amount, _minAmountOutData);
        return _swapUniV2(_from, _to, _amount, minAmountOut, _router);
    }

    function swapBal(
        address _from,
        address _to,
        uint256 _amount,
        MinAmountOutData memory _minAmountOutData,
        address _vault
    ) external pullFromBefore(_from, _amount) pushFromAndToAfter(_from, _to) returns (uint256) {
        uint256 minAmountOut = _calculateMinAmountOut(_from, _to, _amount, _minAmountOutData);
        return _swapBal(_from, _to, _amount, minAmountOut, _vault);
    }

    function swapVelo(
        address _from,
        address _to,
        uint256 _amount,
        MinAmountOutData memory _minAmountOutData,
        address _router
    ) external pullFromBefore(_from, _amount) pushFromAndToAfter(_from, _to) {
        uint256 minAmountOut = _calculateMinAmountOut(_from, _to, _amount, _minAmountOutData);
        _swapVelo(_from, _to, _amount, minAmountOut, _router);
    }

    function swapUniV3(
        address _from,
        address _to,
        uint256 _amount,
        MinAmountOutData memory _minAmountOutData,
        address _router
    ) external pullFromBefore(_from, _amount) pushFromAndToAfter(_from, _to) returns (uint256) {
        uint256 minAmountOut = _calculateMinAmountOut(_from, _to, _amount, _minAmountOutData);
        return _swapUniV3(_from, _to, _amount, minAmountOut, _router);
    }

    function _calculateMinAmountOut(
        address _from,
        address _to,
        uint256 _amountIn,
        MinAmountOutData memory _minAmountOutData
    ) internal view returns (uint256 minAmountOut) {
        if (_minAmountOutData.kind == MinAmountOutKind.Absolute) {
            return _minAmountOutData.absoluteOrBPSValue;
        }

        // Validate input
        CLAggregatorData storage fromAggregatorData = aggregatorData[_from];
        require(address(fromAggregatorData.aggregator) != address(0), "CL aggregator not registered");
        CLAggregatorData storage toAggregatorData = aggregatorData[_to];
        require(address(toAggregatorData.aggregator) != address(0), "CL aggregator not registered");
        require(_minAmountOutData.absoluteOrBPSValue <= PERCENT_DIVISOR, "Invalid BPS value");

        // Get asset prices in target digit precision (18 decimals)
        uint256 fromPriceTargetDigits = _getChainlinkPriceTargetDigits(_from);
        uint256 toPriceTargetDigits = _getChainlinkPriceTargetDigits(_from);

        // Get asset USD amounts in target digit precision (18 decimals)
        uint256 fromAmountUsdTargetDigits =
            (_amountIn * fromPriceTargetDigits) / 10 ** IERC20MetadataUpgradeable(_from).decimals();
        uint256 toAmountUsdTargetDigits =
            fromAmountUsdTargetDigits * _minAmountOutData.absoluteOrBPSValue / PERCENT_DIVISOR;

        minAmountOut = (toAmountUsdTargetDigits * 10 ** IERC20MetadataUpgradeable(_to).decimals()) / toPriceTargetDigits;
    }

    /**
     * @dev Returns an array of all the relevant roles arranged in descending order of privilege.
     *      Subclasses should override this to specify their unique roles arranged in the correct
     *      order, for example, [SUPER-ADMIN, ADMIN, GUARDIAN, STRATEGIST].
     */
    function _cascadingAccessRoles() internal pure override returns (bytes32[] memory) {
        bytes32[] memory cascadingAccessRoles = new bytes32[](3);
        cascadingAccessRoles[0] = DEFAULT_ADMIN_ROLE;
        cascadingAccessRoles[1] = GUARDIAN;
        cascadingAccessRoles[2] = STRATEGIST;
        return cascadingAccessRoles;
    }

    /**
     * @dev Returns {true} if {_account} has been granted {_role}. Subclasses should override
     *      this to specify their unique role-checking criteria.
     */
    function _hasRole(bytes32 _role, address _account) internal view override returns (bool) {
        return hasRole(_role, _account);
    }

    function _getChainlinkPriceTargetDigits(address _token) internal view returns (uint256 price) {
        ChainlinkResponse memory chainlinkResponse = _getCurrentChainlinkResponse(_token);
        ChainlinkResponse memory prevChainlinkResponse =
            _getPrevChainlinkResponse(_token, chainlinkResponse.roundId, chainlinkResponse.decimals);
        require(
            !_chainlinkIsBroken(chainlinkResponse, prevChainlinkResponse)
                && !_chainlinkIsFrozen(chainlinkResponse, _token),
            "PriceFeed: Chainlink must be working and current"
        );
        price = _scaleChainlinkPriceByDigits(uint256(chainlinkResponse.answer), chainlinkResponse.decimals);
    }

    function _getCurrentChainlinkResponse(address _token)
        internal
        view
        returns (ChainlinkResponse memory chainlinkResponse)
    {
        // First, try to get current decimal precision:
        try aggregatorData[_token].aggregator.decimals() returns (uint8 decimals) {
            // If call to Chainlink succeeds, record the current decimal precision
            chainlinkResponse.decimals = decimals;
        } catch {
            // If call to Chainlink aggregator reverts, return a zero response with success = false
            return chainlinkResponse;
        }

        // Secondly, try to get latest price data:
        try aggregatorData[_token].aggregator.latestRoundData() returns (
            uint80 roundId, int256 answer, uint256, /* startedAt */ uint256 timestamp, uint80 /* answeredInRound */
        ) {
            // If call to Chainlink succeeds, return the response and success = true
            chainlinkResponse.roundId = roundId;
            chainlinkResponse.answer = answer;
            chainlinkResponse.timestamp = timestamp;
            chainlinkResponse.success = true;
            return chainlinkResponse;
        } catch {
            // If call to Chainlink aggregator reverts, return a zero response with success = false
            return chainlinkResponse;
        }
    }

    function _getPrevChainlinkResponse(address _token, uint80 _currentRoundId, uint8 _currentDecimals)
        internal
        view
        returns (ChainlinkResponse memory prevChainlinkResponse)
    {
        /*
        * NOTE: Chainlink only offers a current decimals() value - there is no way to obtain the decimal precision used in a 
        * previous round.  We assume the decimals used in the previous round are the same as the current round.
        */

        // Try to get the price data from the previous round:
        try aggregatorData[_token].aggregator.getRoundData(_currentRoundId - 1) returns (
            uint80 roundId, int256 answer, uint256, /* startedAt */ uint256 timestamp, uint80 /* answeredInRound */
        ) {
            // If call to Chainlink succeeds, return the response and success = true
            prevChainlinkResponse.roundId = roundId;
            prevChainlinkResponse.answer = answer;
            prevChainlinkResponse.timestamp = timestamp;
            prevChainlinkResponse.decimals = _currentDecimals;
            prevChainlinkResponse.success = true;
            return prevChainlinkResponse;
        } catch {
            // If call to Chainlink aggregator reverts, return a zero response with success = false
            return prevChainlinkResponse;
        }
    }

    /* Chainlink is considered broken if its current or previous round data is in any way bad. We check the previous round
    * for two reasons:
    *
    * 1) It is necessary data for the price deviation check in case 1,
    * and
    * 2) Chainlink is the PriceFeed's preferred primary oracle - having two consecutive valid round responses adds
    * peace of mind when using or returning to Chainlink.
    */
    function _chainlinkIsBroken(ChainlinkResponse memory _currentResponse, ChainlinkResponse memory _prevResponse)
        internal
        view
        returns (bool)
    {
        return _badChainlinkResponse(_currentResponse) || _badChainlinkResponse(_prevResponse);
    }

    function _badChainlinkResponse(ChainlinkResponse memory _response) internal view returns (bool) {
        // Check for response call reverted
        if (!_response.success) return true;
        // Check for an invalid roundId that is 0
        if (_response.roundId == 0) return true;
        // Check for an invalid timeStamp that is 0, or in the future
        if (_response.timestamp == 0 || _response.timestamp > block.timestamp) return true;
        // Check for non-positive price
        if (_response.answer <= 0) return true;

        return false;
    }

    function _chainlinkIsFrozen(ChainlinkResponse memory _response, address _token) internal view returns (bool) {
        uint256 aggregatorTimeout = aggregatorData[_token].timeout;
        return block.timestamp - _response.timestamp > aggregatorTimeout;
    }

    function _scaleChainlinkPriceByDigits(uint256 _price, uint256 _answerDigits) internal pure returns (uint256) {
        // Convert the price returned by the Chainlink oracle to an 18-digit decimal
        uint256 price;
        if (_answerDigits >= TARGET_DIGITS) {
            // Scale the returned price value down to our target precision
            price = _price / (10 ** (_answerDigits - TARGET_DIGITS));
        } else if (_answerDigits < TARGET_DIGITS) {
            // Scale the returned price value up to our target precision
            price = _price * (10 ** (TARGET_DIGITS - _answerDigits));
        }
        return price;
    }

    /**
     * @dev This function must be called prior to upgrading the implementation.
     *      It's required to wait UPGRADE_TIMELOCK seconds before executing the upgrade.
     *      Strategists and roles with higher privilege can initiate this cooldown.
     */
    function initiateUpgradeCooldown() external {
        _atLeastRole(STRATEGIST);
        upgradeProposalTime = block.timestamp;
    }

    /**
     * @dev This function is called:
     *      - in initialize()
     *      - as part of a successful upgrade
     *      - manually to clear the upgrade cooldown.
     * Guardian and roles with higher privilege can clear this cooldown.
     */
    function clearUpgradeCooldown() public {
        _atLeastRole(GUARDIAN);
        upgradeProposalTime = block.timestamp + FUTURE_NEXT_PROPOSAL_TIME;
    }

    /**
     * @dev This function must be overriden simply for access control purposes.
     *      Only DEFAULT_ADMIN_ROLE can upgrade the implementation once the timelock
     *      has passed.
     */
    function _authorizeUpgrade(address) internal override {
        _atLeastRole(DEFAULT_ADMIN_ROLE);
        require(
            upgradeProposalTime + UPGRADE_TIMELOCK < block.timestamp, "Upgrade cooldown not initiated or still ongoing"
        );
        clearUpgradeCooldown();
    }

    modifier pullFromBefore(address _from, uint256 _amount) {
        IERC20MetadataUpgradeable(_from).safeTransferFrom(msg.sender, address(this), _amount);
        _;
    }

    modifier pushFromAndToAfter(address _from, address _to) {
        _;
        uint256 fromBal = IERC20MetadataUpgradeable(_from).balanceOf(address(this));
        if (fromBal != 0) {
            IERC20MetadataUpgradeable(_from).safeTransfer(msg.sender, fromBal);
        }
        uint256 toBal = IERC20MetadataUpgradeable(_to).balanceOf(address(this));
        if (toBal != 0) {
            IERC20MetadataUpgradeable(_to).safeTransfer(msg.sender, toBal);
        }
    }
}

