// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./SafeMath.sol";
import "./IVaultLibrary.sol";
import "./IfxToken.sol";
import "./IValidator.sol";
import "./IHandle.sol";
import "./IInterest.sol";
import "./IMakerJug.sol";
import "./HandlePausable.sol";

/**
 * @dev Keeps track of time passed and interest rates, storing relevant
        variables. Allows to track and update interest rates according to
        configured external protocols such as MakerDAO's.
 */
contract Interest is
    IInterest,
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    HandlePausable,
    ReentrancyGuardUpgradeable
{
    using SafeMath for uint256;

    /** @dev The Handle contract interface */
    IHandle private handle;
    /** @dev The VaultLibrary contract interface */
    IVaultLibrary private vaultLibrary;

    /** @dev mapping(collateral => cumulative interest rate) */
    mapping(address => uint256) public R;
    /** @dev Date when the interest rate was last globally charged
             i.e. the R value was updated. */
    uint256 public lastChargedDate;

    /** @dev Address from which to fetch external interest rates.
             This currently is the MakerDAO Multi-Collateral-Dai (MCD) Jug
             contract, but could be an IAggregatorInterface in the future if
             loading an average interest rate from different protocols other
             than just DAI. */
    address public interestRatesDataSource;
    /** @dev Time at which the interest rate was last automatically updated
             using the configured data source. */
    uint256 public interestRateLastUpdated;
    /** @dev Struct containing external protocol data needed to fetch info
             from such. Will not be needed if maintaining an aggregator
             interface contract in the future. */
    mapping(address => ExternalAssetData) externalAssetData;
    /** @dev Maximum interest ratio per 1,000 that can be set from an external
             source. */
    uint256 public maxInterestPerMille;

    /** @dev Proxy initialisation function */
    function initialize() public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init();
        __ReentrancyGuard_init();
        lastChargedDate = block.timestamp;
    }

    /**
     * @dev Setter for Handle contract reference
     * @param _handle The Handle contract address
     */
    function setHandleContract(address _handle) public override onlyOwner {
        handle = IHandle(_handle);
        vaultLibrary = IVaultLibrary(handle.vaultLibrary());
    }

    /** @dev Getter for Handle contract address */
    function handleAddress() public view override returns (address) {
        return address(handle);
    }

    /**
     * @dev Setter for interestRatesDataSource.
     * @param source The address for the source contract.
     */
    function setDataSource(address source) external override onlyOwner {
        interestRatesDataSource = source;
    }

    /**
     * @dev Setter for externalAssetData
     * @param collateral The collateral token to set external asset data for.
     * @param makerDaoCollateralIlk The maker "ilk" value for the collateral.
     */
    function setCollateralExternalAssetData(
        address collateral,
        bytes32 makerDaoCollateralIlk
    ) external override onlyOwner {
        externalAssetData[collateral] = ExternalAssetData({
            makerDaoCollateralIlk: makerDaoCollateralIlk
        });
    }

    /**
     * @dev Unsets externalCollateralData for a collateral token.
     * @param collateral The collateral token to delete external asset data for.
     */
    function unsetCollateralExternalAssetData(address collateral)
        external
        override
        onlyOwner
    {
        delete externalAssetData[collateral];
    }

    /**
     * @dev Setter for maxInterestPerMille
     * @param interestPerMille The value to set maxInterestPerMille to
     */
    function setMaxExternalSourceInterest(uint256 interestPerMille)
        external
        override
        onlyOwner
    {
        maxInterestPerMille = interestPerMille;
    }

    /**
     * @dev Attempts to trigger an interest rate update according to the
            currently configured data source.
            It is important that this function does not revert as it is called
            from different parts of the protocol.
     */
    function tryUpdateRates() external override {
        // Abort update if the data source is not set.
        if (interestRatesDataSource == address(0)) return;
        // Abort update if the cache time of 1 day is still valid.
        if (block.timestamp < interestRateLastUpdated + 1 days) return;
        updateRates();
    }

    /**
     * @dev Updates the interest rate via the data source
     */
    function updateRates() public override notPaused {
        address[] memory collateralTokens = handle.getAllCollateralTypes();
        uint256 j = collateralTokens.length;
        IHandle.CollateralData memory data;
        uint256 interestRate;
        for (uint256 i = 0; i < j; i++) {
            interestRate = fetchRate(collateralTokens[i]);
            if (interestRate == 0) continue;
            data = handle.getCollateralDetails(collateralTokens[i]);
            // Update collateral with fetched interest.
            handle.setCollateralToken(
                collateralTokens[i],
                data.mintCR,
                data.liquidationFee,
                // New interest rate as a per mille ratio (1/1000th, 1 decimal).
                interestRate
            );
        }
        // Update the fetch time for caching purposes.
        interestRateLastUpdated = block.timestamp;
    }

    /**
     * @dev Fetches the interest rate for a token directly from the data source.
               This is not the current Handle protocol's interest rate but rather
               the current rate from the data source assigned to this contract,
               which may only be set to Handle after the cache time has expired.
            The current implementation simply reads the interest rate for
            the input token from the MCD Jug contract as a per mille ratio.
            In the future the data source could be changed to an intermediate
            contract that fetches the rates from multiple protocols and returns
            an averaged value.
            Returns the interest rate as a per mille (1/1000th, 1 decimal) ratio.
       @param token The token to find the interest rate for
     */
    function fetchRate(address token) public view override returns (uint256) {
        if (interestRatesDataSource == address(0)) return 0;
        ExternalAssetData storage data = externalAssetData[token];
        if (data.makerDaoCollateralIlk == "") return 0;
        IMakerJug jug = IMakerJug(interestRatesDataSource);
        uint256 unit = 10**27;
        // The maker stability fee is the base rate plus the collateral rate.
        uint256 stabilityPerSecond =
            jug.base().add(jug.ilks(data.makerDaoCollateralIlk).duty);
        // The rate is > 1 unit (10e27), the unit must be subtracted.
        if (stabilityPerSecond < unit) return 0;
        stabilityPerSecond = stabilityPerSecond.sub(unit);
        uint256 N = 365 * 24 * 60 * 60;
        // Maker compounds the interest, therefore the correct calculation
        // here would be (stabilityPerSecond ^ N), but this calculation is
        // too large and overflows. Therefore a linear approximation is used
        // which results in a similar value but not the same.
        uint256 rate = (stabilityPerSecond * N).mul(1000).div(unit);
        // Round rate down to the nearest half percent.
        rate = ((rate + 5 - 1) / 5) * 5 - 5;
        return
            maxInterestPerMille > 0 && rate > maxInterestPerMille
                ? maxInterestPerMille
                : rate;
    }

    /**
     * @dev Writes the current R value to storage. Only needed before
               updating the interest rate as this affects the rate over time
               and therefore the cumulative rate.
     */
    function charge() external override notPaused {
        // Abort if already called this block.
        if (lastChargedDate == block.timestamp) return;
        // Get the current R values and write to storage.
        (uint256[] memory currentR, address[] memory collateralTokens) =
            getCurrentR();
        uint256 l = currentR.length;
        assert(l == collateralTokens.length);
        for (uint256 i = 0; i < l; i++) {
            address token = collateralTokens[i];
            R[token] = currentR[i];
        }
        lastChargedDate = block.timestamp;
    }

    /**
     * @dev Returns the stored R value plus the delta cumulative rate
               applying the current interest rate for each collateral token
     */
    function getCurrentR()
        public
        view
        override
        returns (uint256[] memory currentR, address[] memory collateralTokens)
    {
        collateralTokens = handle.getAllCollateralTypes();
        uint256 l = collateralTokens.length;
        currentR = new uint256[](l);
        uint256 delta = block.timestamp.sub(lastChargedDate);
        uint256 interestRate;
        address token;
        for (uint256 i = 0; i < l; i++) {
            token = collateralTokens[i];
            interestRate = handle
                .getCollateralDetails(token)
                .interestRate
                .mul(1 ether)
                .div(1000);
            currentR[i] = R[token].add(interestRate.mul(delta).div(365 days));
        }
    }

    /** @dev Protected UUPS upgrade authorization function */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}

