//SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.17;
import "./Ownable.sol";
import "./GLPManagerInterface.sol";
import "./plvGLPInterface.sol";
import "./ERC20Interface.sol";
import "./Whitelist.sol";

//TODO: optimize integer sizes for gas efficiency?

/** @title Oracle for Plutus Vault GLP employing moving average calculations for pricing
    @author Lodestar Finance & Plutus DAO
    @notice This contract uses a moving average calculation to report a plvGLP/GLP exchange
    rate. The "window size" is adjustable to allow for flexibility in calculation parameters. The price
    returned from the getPlvGLPPrice function is denominated in USD wei.
*/
contract plvGLPOracle is Ownable {
    uint256 public averageIndex;
    uint256 public windowSize;

    address public GLP;
    address public GLPManager;
    address public plvGLP;
    address public whitelist;

    uint256 private constant BASE = 1e18;
    uint256 private constant DECIMAL_DIFFERENCE = 1e6;
    uint256 private constant MAX_SWING = 10000000000000000; //1%
    bool public constant isGLPOracle = true;

    struct IndexInfo {
        uint256 timestamp;
        uint256 recordedIndex;
    }

    IndexInfo[] public HistoricalIndices;

    event IndexAlert(uint256 previousIndex, uint256 possiblyBadIndex, uint256 timestamp);
    event updatePosted(uint256 averageIndex, uint256 timestamp);

    constructor(address _GLP, address _GLPManager, address _plvGLP, address _whitelist, uint256 _windowSize) {
        GLP = _GLP;
        GLPManager = _GLPManager;
        plvGLP = _plvGLP;
        whitelist = _whitelist;
        windowSize = _windowSize;
        uint256 index = getPlutusExchangeRate();
        require(index > 0, "First index cannot be zero.");
        //initialize indices, this push will be stored in position 0
        HistoricalIndices.push(IndexInfo(block.timestamp, index));
    }

    /**
        @notice Pulls requisite data from GLP contract to calculate the current price of GLP
        @return Returns the price of GLP denominated in USD wei.
     */
    function getGLPPrice() public view returns (uint256) {
        //retrieve the minimized AUM from GLP Manager Contract
        uint256 glpAUM = GLPManagerInterface(GLPManager).getAum(false);
        //retrieve the total supply of GLP
        uint256 glpSupply = ERC20Interface(GLP).totalSupply();
        //GLP Price = AUM / Total Supply
        uint256 price = (glpAUM / glpSupply) * DECIMAL_DIFFERENCE;
        return price;
    }

    /**
        @notice Pulls requisite data from Plutus Vault contract to calculate the current exchange rate.
        @return Returns the current plvGLP/GLP exchange rate directly from Plutus vault contract.
     */
    function getPlutusExchangeRate() public view returns (uint256) {
        //retrieve total assets from plvGLP contract
        uint256 totalAssets = plvGLPInterface(plvGLP).totalAssets();
        //retrieve total supply from plvGLP contract
        uint256 totalSupply = ERC20Interface(plvGLP).totalSupply();
        //plvGLP/GLP Exchange Rate = Total Assets / Total Supply
        uint256 exchangeRate = (totalAssets * BASE) / totalSupply;
        return exchangeRate;
    }

    /**
        @notice Computes the moving average over a period of "windowSize". For the initialization period,
        the average is computed over the length of the indices array.
        @return Returns the moving average of the index over the specified window.
     */
    function computeAverageIndex() public returns (uint256) {
        uint256 latestIndexing = HistoricalIndices.length - 1;
        uint256 sum;
        if (latestIndexing <= windowSize) {
            for (uint256 i = 0; i < latestIndexing; i++) {
                sum += HistoricalIndices[i].recordedIndex;
            }
            averageIndex = sum / HistoricalIndices.length;
            return averageIndex;
        } else {
            uint256 firstIndex = latestIndexing - windowSize + 1;
            for (uint256 i = firstIndex; i <= latestIndexing; i++) {
                sum += HistoricalIndices[i].recordedIndex;
            }
            averageIndex = sum / windowSize;
            return averageIndex;
        }
    }

    /**
        @notice Returns the value of the previously accepted exchange rate.
     */
    function getPreviousIndex() public view returns (uint256) {
        uint256 previousIndexing = HistoricalIndices.length - 1;
        uint256 previousIndex = HistoricalIndices[previousIndexing].recordedIndex;
        return previousIndex;
    }

    /**
        @notice Checks the currently reported exchange rate against the last accepted exchange rate.
        Requested updates are compared against a range of +/- 1% of the previous exchange rate.
        @param currentIndex the currently reported index from Plutus to check swing on
        @return returns TRUE if requested update is within the bounds of maximum swing, returns FALSE otherwise.
     */
    function checkSwing(uint256 currentIndex) public returns (bool) {
        uint256 previousIndex = getPreviousIndex();
        uint256 allowableSwing = (previousIndex * MAX_SWING) / BASE;
        uint256 minSwing = previousIndex - allowableSwing;
        uint256 maxSwing = previousIndex + allowableSwing;
        if (currentIndex > maxSwing || currentIndex < minSwing) {
            emit IndexAlert(previousIndex, currentIndex, block.timestamp);
            return false;
        }
        return true;
    }

    /**
        @notice Update the current, cumulative and average indices when required conditions are met.
        If the price fails to update, the posted price will fall back on the last previously 
        accepted average index. Access is restricted to only whitelisted addresses.
        @dev we only ever update the index if requested update is within +/- 1% of previously accepted
        index and update threshold has been reached.
     */
    function updateIndex() external {
        require(Whitelist(whitelist).isWhitelisted(msg.sender), "NOT_AUTHORIZED");
        uint256 currentIndex = getPlutusExchangeRate();
        uint256 previousIndex = getPreviousIndex();
        bool indexCheck = checkSwing(currentIndex);
        if (!indexCheck) {
            currentIndex = previousIndex;
            HistoricalIndices.push(IndexInfo(block.timestamp, currentIndex));
            averageIndex = computeAverageIndex();
            emit updatePosted(averageIndex, block.timestamp);
        } else {
            HistoricalIndices.push(IndexInfo(block.timestamp, currentIndex));
            averageIndex = computeAverageIndex();
            emit updatePosted(averageIndex, block.timestamp);
        }
    }

    /**
        @notice Computes the TWAP price of plvGLP based on the current price of GLP and moving average of the
        plvGLP/GLP exchange rate.
        @return Returns the TWAP price of plvGLP denominated in USD wei.
     */
    function getPlvGLPPrice() external view returns (uint256) {
        uint256 glpPrice = getGLPPrice();
        uint256 plvGlpPrice = (averageIndex * glpPrice) / BASE;
        return plvGlpPrice;
    }

    //* ADMIN FUNCTIONS */

    event newGLPAddress(address oldGLPAddress, address newGLPAddress);
    event newGLPManagerAddress(address oldManagerAddress, address newManagerAddress);
    event newPlvGLPAddress(address oldPlvGLPAddress, address newPlvGLPAddress);
    event windowSizeUpdated(uint256 oldWindowSize, uint256 newWindowSize);

    /**
        @notice Admin function to update the address of GLP, restricted to only be 
        usable by the contract owner.
     */
    function _updateGlpAddress(address _newGlpAddress) external onlyOwner {
        address oldGLPAddress = GLP;
        GLP = _newGlpAddress;
        emit newGLPAddress(oldGLPAddress, GLP);
    }

    /**
        @notice Admin function to update the address of the GLP Manager Contract, restricted to only be 
        usable by the contract owner.
     */
    function _updateGlpManagerAddress(address _newGlpManagerAddress) external onlyOwner {
        address oldManagerAddress = GLPManager;
        GLPManager = _newGlpManagerAddress;
        emit newGLPManagerAddress(oldManagerAddress, GLPManager);
    }

    /**
        @notice Admin function to update the address of plvGLP, restricted to only be 
        usable by the contract owner.
     */
    function _updatePlvGlpAddress(address _newPlvGlpAddress) external onlyOwner {
        address oldPlvGLPAddress = plvGLP;
        plvGLP = _newPlvGlpAddress;
        emit newPlvGLPAddress(oldPlvGLPAddress, plvGLP);
    }

    /**
        @notice Admin function to update the moving average window size, restricted to only be 
        usable by the contract owner.
     */
    function _updateWindowSize(uint256 _newWindowSize) external onlyOwner {
        uint256 oldWindowSize = windowSize;
        windowSize = _newWindowSize;
        emit windowSizeUpdated(oldWindowSize, windowSize);
    }
}

