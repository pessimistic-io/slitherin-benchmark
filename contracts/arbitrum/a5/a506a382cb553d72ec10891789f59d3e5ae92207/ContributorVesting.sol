// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

// Interfaces
import {IERC20} from "./IERC20.sol";

// Libraries
import {SafeERC20} from "./SafeERC20.sol";

// Contracts
import {Ownable} from "./Ownable.sol";

/// @title DAO Contributor Vesting
/// @author Jones DAO
/// @notice Allows to add beneficiaries for token vesting
contract ContributorVesting is Ownable {
    using SafeERC20 for IERC20;

    // Token
    IERC20 public token;

    // Structure of each vest
    struct Vest {
        uint8 role; // the role of the beneficiary
        uint8 tier; // vesting tier of the beneficiary
        uint256 released; // the amount of Token released to the beneficiary
        uint256 startTime; // start time of the vesting
        uint256 lastReleaseTime; // last time vest released
        uint256 pricePerToken; // JONES token price to be considered during vesting with 2 digit precision (e.g. 7.70 is 770)
    }

    // The mapping of vested beneficiary (beneficiary address => Vest)
    mapping(address => Vest) public vestedBeneficiaries;

    // Vesting tiers
    mapping(uint8 => mapping(uint256 => uint256)) public vestingTiers;

    // No. of beneficiaries
    uint256 public noOfBeneficiaries;

    // Three years in seconds constant
    uint256 private constant threeYears = 94670856;

    constructor(address _tokenAddress) {
        require(_tokenAddress != address(0), "Token address cannot be 0");

        token = IERC20(_tokenAddress);
        vestingTiers[0][4] = 3700000000000000000000000;
        vestingTiers[0][5] = 5500000000000000000000000;
        vestingTiers[0][6] = 7300000000000000000000000;
        vestingTiers[0][7] = 9800000000000000000000000;
        vestingTiers[0][8] = 12200000000000000000000000;
        vestingTiers[0][9] = 15300000000000000000000000;
        vestingTiers[0][10] = 18000000000000000000000000;
        vestingTiers[1][4] = 2200000000000000000000000;
        vestingTiers[1][5] = 3200000000000000000000000;
        vestingTiers[1][6] = 4300000000000000000000000;
        vestingTiers[1][7] = 5800000000000000000000000;
        vestingTiers[1][8] = 7200000000000000000000000;
        vestingTiers[1][9] = 9000000000000000000000000;
        vestingTiers[1][10] = 11200000000000000000000000;
        vestingTiers[2][4] = 1500000000000000000000000;
        vestingTiers[2][5] = 2300000000000000000000000;
        vestingTiers[2][6] = 3000000000000000000000000;
        vestingTiers[2][7] = 4000000000000000000000000;
        vestingTiers[2][8] = 5000000000000000000000000;
        vestingTiers[2][9] = 6300000000000000000000000;
        vestingTiers[2][10] = 7900000000000000000000000;
    }

    /*---- EXTERNAL FUNCTIONS FOR OWNER ----*/

    /**
     * @notice Adds a beneficiary to the contract. Only owner can call this.
     * @param _beneficiary the address of the beneficiary
     * @param _role the role of the beneficiary
     * @param _tier tier of the beneficiary
     * @param _startTime start time of the vesting
     * @param _pricePerToken JONES token price to be considered during vesting with 2 digit precision (e.g. 7.70 is 770)
     */
    function addBeneficiary(
        address _beneficiary,
        uint8 _role,
        uint8 _tier,
        uint256 _startTime,
        uint256 _pricePerToken
    ) public onlyOwner returns (bool) {
        require(
            _beneficiary != address(0),
            "Beneficiary cannot be a 0 address"
        );
        require(_role >= 0 && _tier <= 2, "Role should be between 0 and 2");
        require(_tier >= 4 && _tier <= 10, "Tier should be between 4 and 10");
        require(
            vestedBeneficiaries[_beneficiary].tier == 0,
            "Cannot add the same beneficiary again"
        );
        require(_pricePerToken > 0, "Price per token should be larger than 0");

        uint256 initialReleaseAmount = 0;
        uint256 realLatestRelease = _startTime;
        if (block.timestamp > _startTime) {
            realLatestRelease = block.timestamp;
            initialReleaseAmount =
                ((vestingTiers[_role][_tier] / _pricePerToken) *
                    (block.timestamp - _startTime)) /
                threeYears;
            token.safeTransfer(_beneficiary, initialReleaseAmount);
        }

        vestedBeneficiaries[_beneficiary] = Vest(
            _role,
            _tier,
            initialReleaseAmount,
            _startTime,
            realLatestRelease,
            _pricePerToken
        );

        noOfBeneficiaries += 1;

        emit AddBeneficiary(
            _beneficiary,
            _role,
            _tier,
            initialReleaseAmount,
            vestTimeLeft(_beneficiary),
            _startTime,
            _pricePerToken
        );

        return true;
    }

    /**
     * @notice Removes a beneficiary from the contract hence ending their vesting. Only owner can call this.
     * @param _beneficiary the address of the beneficiary
     * @return whether beneficiary was removed
     */
    function removeBeneficiary(address _beneficiary)
        external
        onlyOwner
        returns (bool)
    {
        require(
            _beneficiary != address(0),
            "Beneficiary cannot be a 0 address"
        );
        require(
            vestedBeneficiaries[_beneficiary].tier != 0,
            "Cannot remove a beneficiary which has not been added"
        );

        if (releasableAmount(_beneficiary) > 0) {
            release(_beneficiary);
        }

        vestedBeneficiaries[_beneficiary] = Vest(0, 0, 0, 0, 0, 0);

        noOfBeneficiaries -= 1;

        emit RemoveBeneficiary(_beneficiary);

        return true;
    }

    /**
     * @notice Updates a beneficiary's address. Only owner can call this.
     * @param _oldAddress the address of the beneficiary
     * @param _newAddress new tier of the beneficiary
     * @return whether beneficiary was updated
     */
    function updateBeneficiaryAddress(address _oldAddress, address _newAddress)
        external
        onlyOwner
        returns (bool)
    {
        require(
            vestedBeneficiaries[_oldAddress].tier != 0,
            "Vesting for this address doesnt exist"
        );

        vestedBeneficiaries[_newAddress] = vestedBeneficiaries[_oldAddress];
        vestedBeneficiaries[_oldAddress] = Vest(0, 0, 0, 0, 0, 0);

        emit UpdateBeneficiaryAddress(_oldAddress, _newAddress);

        return true;
    }

    /**
     * @notice Updates a beneficiary's tier. Only owner can call this.
     * @param _beneficiary the address of the beneficiary
     * @param _tier new tier of the beneficiary
     * @return whether beneficiary was updated
     */
    function updateBeneficiaryTier(address _beneficiary, uint8 _tier)
        external
        onlyOwner
        returns (bool)
    {
        Vest memory vBeneficiary = vestedBeneficiaries[_beneficiary];
        require(_tier >= 4 && _tier <= 10, "Tier should be between 4 and 10");
        require(
            _beneficiary != address(0),
            "Beneficiary cannot be a 0 address"
        );
        require(
            vBeneficiary.tier != 0,
            "Cannot remove a beneficiary which has not been added yet"
        );
        require(vBeneficiary.tier != _tier, "Beneficiary already in this tier");
        require(
            block.timestamp < vBeneficiary.startTime + threeYears &&
                block.timestamp > vBeneficiary.startTime,
            "Not within vesting period"
        );

        if (releasableAmount(_beneficiary) > 0) {
            release(_beneficiary);
        }

        uint8 oldTier = vBeneficiary.tier;
        uint256 beneficiaryTotalAmount = vestingTiers[vBeneficiary.role][
            _tier
        ] / vBeneficiary.pricePerToken;
        uint256 releaseLeft = beneficiaryTotalAmount -
            ((beneficiaryTotalAmount *
                (block.timestamp - vBeneficiary.startTime)) / threeYears);

        vestedBeneficiaries[_beneficiary].tier = _tier;

        emit UpdateBeneficiaryTier(_beneficiary, oldTier, _tier, releaseLeft);

        return true;
    }

    /**
     * @notice Allows updating of vesting tier token release amount.
     * @dev Use 20 digit precision
     * @param _role role of the beneficiary
     * @param _tier tier number
     * @param _amount amount of JONES tokens in three years
     */
    function updateTierAmount(
        uint8 _role,
        uint8 _tier,
        uint256 _amount
    ) public onlyOwner {
        require(_role >= 0 && _role <= 2, "Role should be between 0 and 2");
        require(_tier >= 4 && _tier <= 10, "Tier should be between 4 and 10");
        require(_amount > 0, "Amount must be greater than 0");
        vestingTiers[_role][_tier] = _amount;
    }

    /**
     * @notice Allows updating of price per token for a certain beneficiary.
     * @param _beneficiary the address of the beneficiary
     * @param _price with 2 digit precision (7.70 is 770)
     */
    function updatePricePerToken(address _beneficiary, uint256 _price)
        public
        onlyOwner
    {
        require(_price > 0, "Price must be greater than 0");
        require(
            vestedBeneficiaries[_beneficiary].tier != 0,
            "Cannot modify a beneficiary which has not been added to vesting"
        );
        vestedBeneficiaries[_beneficiary].pricePerToken = _price;
    }

    /**
     * @notice Allows releasing tokens earlier for a certain beneficiary.
     * @param _beneficiary the address of the beneficiary
     * @param _time how much time worth of tokens to unlock in seconds
     */
    function earlyUnlock(address _beneficiary, uint256 _time) public onlyOwner {
        require(
            vestedBeneficiaries[_beneficiary].tier != 0,
            "Beneficiary must exist"
        );
        if (releasableAmount(_beneficiary) > 0) {
            release(_beneficiary);
        }
        Vest memory vBeneficiary = vestedBeneficiaries[_beneficiary];
        require(
            block.timestamp < vBeneficiary.startTime + threeYears &&
                block.timestamp > vBeneficiary.startTime,
            "Not within vesting period"
        );

        uint256 realUnlockTime = _time;
        if (block.timestamp < vBeneficiary.startTime + threeYears - _time) {
            realUnlockTime =
                vBeneficiary.startTime +
                threeYears -
                block.timestamp;
        }

        // calculate amount to release
        uint256 beneficiaryTotalAmount = vestingTiers[vBeneficiary.role][
            vBeneficiary.tier
        ] / vBeneficiary.pricePerToken;
        uint256 toRelease = (beneficiaryTotalAmount * realUnlockTime) /
            threeYears;

        vestedBeneficiaries[_beneficiary].startTime -= realUnlockTime;
        token.safeTransfer(_beneficiary, toRelease);
        emit EarlyUnlock(_beneficiary, realUnlockTime, toRelease);
    }

    /**
     * @notice Allows owner to withdraw tokens from the contract.
     * @param _amount amount of JONES to withdraw
     */
    function withdrawToken(uint256 _amount) public onlyOwner {
        require(_amount > 0, "Amount must be greater than 0");
        token.safeTransfer(msg.sender, _amount);
    }

    /*---- EXTERNAL/PUBLIC FUNCTIONS ----*/

    /**
     * @notice Transfers vested tokens to beneficiary.
     * @param beneficiary the beneficiary to release the JONES to
     */
    function release(address beneficiary) public returns (uint256 unreleased) {
        unreleased = releasableAmount(beneficiary);

        require(unreleased > 0, "No releasable amount");
        require(
            vestedBeneficiaries[beneficiary].lastReleaseTime + 300 <=
                block.timestamp,
            "Can only release every 5 minutes"
        );

        vestedBeneficiaries[beneficiary].released += unreleased;

        vestedBeneficiaries[beneficiary].lastReleaseTime = block.timestamp;

        token.safeTransfer(beneficiary, unreleased);

        emit TokensReleased(beneficiary, unreleased);
    }

    /**
     * @notice Transfers vested tokens to message sender.
     */
    function selfRelease() public {
        release(msg.sender);
    }

    /*---- VIEWS ----*/

    /**
     * @notice Calculates the amount that has already vested but hasn't been released yet.
     * @param beneficiary address of the beneficiary
     */
    function releasableAmount(address beneficiary)
        public
        view
        returns (uint256)
    {
        Vest memory vBeneficiary = vestedBeneficiaries[beneficiary];
        uint256 beneficiaryTotalAmount = vestingTiers[vBeneficiary.role][
            vBeneficiary.tier
        ] / vBeneficiary.pricePerToken;

        if (block.timestamp > vBeneficiary.startTime + threeYears) {
            // if we are past vest end
            return
                (beneficiaryTotalAmount *
                    ((vBeneficiary.startTime + threeYears) -
                        vBeneficiary.lastReleaseTime)) / threeYears;
        } else if (block.timestamp < vBeneficiary.startTime) {
            // if we are before vest start
            return 0;
        } else {
            // if we are during vest
            return
                (beneficiaryTotalAmount *
                    (block.timestamp - vBeneficiary.lastReleaseTime)) /
                threeYears;
        }
    }

    /**
     * @notice Calculates seconds left until vesting ends.
     * @param beneficiary address of the beneficiary
     */
    function vestTimeLeft(address beneficiary) public view returns (uint256) {
        uint256 vestingEnd = vestedBeneficiaries[beneficiary].startTime +
            threeYears;
        return
            block.timestamp < vestingEnd ? (block.timestamp - vestingEnd) : 0;
    }

    /*---- EVENTS ----*/

    event TokensReleased(address beneficiary, uint256 amount);

    event AddBeneficiary(
        address beneficiary,
        uint8 role,
        uint8 tier,
        uint256 initialReleaseAmount,
        uint256 duration,
        uint256 timeLeft,
        uint256 pricePerToken
    );

    event RemoveBeneficiary(address beneficiary);

    event UpdateBeneficiaryTier(
        address beneficiary,
        uint8 oldTier,
        uint8 newTier,
        uint256 vestingLeft
    );

    event UpdateBeneficiaryAddress(address oldAddress, address newAddress);

    event EarlyUnlock(address beneficiary, uint256 time, uint256 amount);
}

