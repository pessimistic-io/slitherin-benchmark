// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./IOracle.sol";
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./ERC20.sol";
import "./AccessControl.sol";

/**
 * @notice Oracle contract that aggregates multiple oracles to calculate prices
 */
contract AggregateOracle is IOracle, AccessControl {

    /// @notice Price sources
    IOracle[] public sources;

    /**
     * @notice Initializes the upgradeable contract with the provided parameters
     * @dev _sources[i].getPrice is called as a form of input validation
     */
    function initialize(IOracle[] memory _sources, address _addressProvider) external initializer {
        __AccessControl_init(_addressProvider);
        sources = _sources;
        for (uint i = 0; i<_sources.length; i++) {
            _sources[i].getPrice(provider.networkToken());
        }
    }

    /**
     * @notice Set the underlying oracles that will be used to calculate prices
     */
    function setSources(IOracle[] memory _sources) external restrictAccess(GOVERNOR) {
        sources = _sources;
        for (uint i = 0; i<_sources.length; i++) {
            _sources[i].getPrice(provider.networkToken());
        }
    }

    /**
     * @notice Return the list of all sources
     */
    function getSources() external view returns (address[] memory _sources) {
        _sources = new address[](sources.length);
        for (uint i = 0; i<sources.length; i++) {
            _sources[i] = address(sources[i]);
        }
    }

    /// @inheritdoc IOracle
    function getPrice(address token) public view returns (uint price) {
        uint256 sum = 0;
        uint256 validSources = 0;

        for (uint256 i = 0; i < sources.length; i++) {
            try sources[i].getPrice(token) returns (uint256 sourcePrice) {
                sum += sourcePrice;
                validSources++;
            } catch {
                // Ignore source failure
            }
        }

        require(validSources > 0, "All price sources failed");
        price = sum / validSources;
    }

    /// @inheritdoc IOracle
    function getPriceInTermsOf(address token, address inTermsOf) public view returns (uint price) {
        uint256 sum = 0;
        uint256 validSources = 0;

        for (uint256 i = 0; i < sources.length; i++) {
            try sources[i].getPriceInTermsOf(token, inTermsOf) returns (uint256 sourcePrice) {
                sum += sourcePrice;
                validSources++;
            } catch {
                // Ignore source failure
            }
        }

        require(validSources > 0, "All price sources failed");
        price = sum / validSources;
    }

    /// @inheritdoc IOracle
    function getValue(address token, uint amount) external view returns (uint value) {
        uint256 price = getPrice(token);
        uint decimals = 10**ERC20(token).decimals();
        value = amount*uint(price)/decimals;
    }

    /// @inheritdoc IOracle
    function getValueInTermsOf(address token, uint amount, address inTermsOf) external view returns (uint value) {
        uint256 price = getPriceInTermsOf(token, inTermsOf);
        uint decimals = 10**ERC20(token).decimals();
        value = (price * amount) / decimals;
    }

}
