// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

import "./ERC20.sol";
import "./ReentrancyGuard.sol";
import "./OwnableWithoutContext.sol";

import "./IIncidentReport.sol";

import "./DateTime.sol";

/**
 * @notice Cover Right Tokens
 *
 *         ERC20 tokens that represent the cover you bought
 *         It is a special token:
 *             1) Can not be transferred to other addresses
 *             2) Has an expiry date
 *
 *         A new crToken will be deployed for each month's policies for a pool
 *         Each crToken will ended at the end timestamp of each month
 *
 *         To calculate a user's balance, we use coverFrom to record it.
 *         E.g.  CRToken CR-JOE-2022-8
 *               You bought X amount at timestamp t1 (in 2022-6 ~ 2022-8)
 *               coverStartFrom[yourAddress][t1] += X
 *
 *         When used for claiming, check your crTokens
 *             1) Not expired
 *             2) Not bought too close to the report timestamp
 *
 */
contract CoverRightToken is ERC20, ReentrancyGuard {
    // ---------------------------------------------------------------------------------------- //
    // ************************************* Constants **************************************** //
    // ---------------------------------------------------------------------------------------- //

    // Generation of crToken
    // Same as the generation of the priority pool (when this token was deployed)
    uint256 public immutable generation;

    // Expiry date (always the last timestamp of a month)
    uint256 public immutable expiry;

    // Pool id for this crToken
    uint256 public immutable poolId;

    // Those covers bought within 2 days will be excluded
    // TODO: test will set it as 0
    uint256 public constant EXCLUDE_DAYS = 2;

    // ---------------------------------------------------------------------------------------- //
    // ************************************* Variables **************************************** //
    // ---------------------------------------------------------------------------------------- //

    // Policy center address
    address public policyCenter;

    // Incident report address
    address public incidentReport;

    // Payout pool address
    address public payoutPool;

    // Pool name for this crToken
    string public poolName;

    // User address => start timestamp => cover amount
    mapping(address => mapping(uint256 => uint256)) public coverStartFrom;

    // ---------------------------------------------------------------------------------------- //
    // ************************************* Constructor ************************************** //
    // ---------------------------------------------------------------------------------------- //

    constructor(
        string memory _poolName,
        uint256 _poolId,
        string memory _name,
        uint256 _expiry,
        uint256 _generation,
        address _policyCenter,
        address _incidentReport,
        address _payoutPool
    ) ERC20(_name, "crToken") {
        expiry = _expiry;

        poolName = _poolName;
        poolId = _poolId;
        generation = _generation;

        policyCenter = _policyCenter;
        incidentReport = _incidentReport;
        payoutPool = _payoutPool;
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************** Modifiers *************************************** //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Only called from permitted addresses
     *
     *         Permitted addresses:
     *            1) Policy center
     *            2) Payout pool
     *
     *         For policyCenter, when deploying new crTokens, the policyCenter address is still not initialized,
     *         so we only skip the test when policyCenter is address(0)
     */
    modifier onlyPermitted() {
        if (policyCenter != address(0)) {
            require(
                msg.sender == policyCenter || msg.sender == payoutPool,
                "Not permitted"
            );
        }
        _;
    }

    /**
     * @notice Override the decimals funciton
     *
     *         Cover right token is minted with reference to the cover amount he bought
     *         So keep the decimals the same with USDC
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************ Main Functions ************************************ //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Mint new crTokens when buying covers
     *
     * @param _poolId Pool id
     * @param _user   User address
     * @param _amount Amount to mint
     */
    function mint(
        uint256 _poolId,
        address _user,
        uint256 _amount
    ) external onlyPermitted nonReentrant {
        require(_amount > 0, "Zero Amount");
        require(_poolId == poolId, "Wrong pool id");

        // uint256 effectiveFrom = _getEOD(
        //     block.timestamp + EXCLUDE_DAYS * 1 days
        // );

        // Start from today's last timestamp
        uint256 effectiveFrom = _getEOD(block.timestamp);

        coverStartFrom[_user][effectiveFrom] += _amount;

        _mint(_user, _amount);
    }

    /**
     * @notice Burn crTokens to claim
     *         Only callable from policyCenter
     *
     * @param _poolId Pool id
     * @param _user   User address
     * @param _amount Amount to burn
     */
    function burn(
        uint256 _poolId,
        address _user,
        uint256 _amount
    ) external onlyPermitted nonReentrant {
        require(_amount > 0, "Zero Amount");
        require(_poolId == poolId, "Wrong pool id");

        _burn(_user, _amount);
    }

    /**
     * @notice Get the claimable amount of a user
     *         Claimable means "without those has passed the expiry date"
     *
     * @param _user User address
     *
     * @return claimable Claimable balance
     */
    function getClaimableOf(address _user) external view returns (uint256) {
        uint256 exclusion = getExcludedCoverageOf(_user);
        uint256 balance = balanceOf(_user);

        if (exclusion > balance) return 0;
        else return balance - exclusion;
    }

    /**
     * @notice Get the excluded amount of a user
     *         Excluded means "without those are bought within a short time before voteTimestamp"
     *
     *         Only count the corresponding one report (voteTimestamp)
     *         Each crToken & priorityPool has a generation
     *         And should get the correct report with this "Generation"
     *             - poolReports(poolId, generation)
     *
     * @param _user User address
     *
     * @return exclusion Amount not able to claim because cover period has ended
     */
    function getExcludedCoverageOf(address _user)
        public
        view
        returns (uint256 exclusion)
    {
        IIncidentReport incident = IIncidentReport(incidentReport);

        // Get the report amount for this pool
        // If report amount is 0, generation should be 1 and no excluded amount
        // If report amount > 0, the effective report should be amount - 1
        uint256 reportAmount = incident.getPoolReportsAmount(poolId);

        if (reportAmount > 0 && generation <= reportAmount) {
            // Only count for the valid report
            // E.g. Current report amount is 3, then for generation 1 crToken,
            //      its corresponding report index (in the array) is 0
            uint256 validReportId = incident.poolReports(
                poolId,
                generation - 1
            );

            (, , , uint256 voteTimestamp, , , , , uint256 result, , ) = incident
                .reports(validReportId);

            // If the result is not PASS, the voteTimestamp should not be counted
            if (result == 1) {
                // Check those bought within 2 days
                for (uint256 i; i < EXCLUDE_DAYS; ) {
                    if (voteTimestamp > i * 1 days) {
                        // * For local test EXCLUDE_DAYS can be set as 0 to avoid underflow
                        // * For mainnet or testnet, will never underflow
                        uint256 date = _getEOD(voteTimestamp - (i * 1 days));

                        exclusion += coverStartFrom[_user][date];
                    }
                    unchecked {
                        ++i;
                    }
                }
            }
        }
    }

    /**
     * @notice Get the timestamp at the end of the day
     *
     * @param _timestamp Timestamp to be transformed
     *
     * @return endTimestamp End timestamp of that day
     */
    function _getEOD(uint256 _timestamp) private pure returns (uint256) {
        (uint256 year, uint256 month, uint256 day) = DateTimeLibrary
            .timestampToDate(_timestamp);
        return
            DateTimeLibrary.timestampFromDateTime(year, month, day, 23, 59, 59);
    }

    /**
     * @notice Hooks before token transfer
     *         - Can burn expired crTokens (send to zero address)
     *         - Can be minted or used for claim
     *         Other transfers are banned
     *
     * @param from From address
     * @param to   To address
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256
    ) internal view override {
        if (block.timestamp > expiry) {
            require(to == address(0), "Expired crToken");
        }

        // crTokens can only be used for claim
        if (from != address(0) && to != address(0)) {
            require(to == policyCenter, "Only to policyCenter");
        }
    }
}

