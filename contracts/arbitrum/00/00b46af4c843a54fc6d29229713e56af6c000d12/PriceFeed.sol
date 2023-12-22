// SPDX-License-Identifier: MIT

pragma solidity ^0.8.14;
import "./IPriceFeed.sol";
import "./IOracle.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./CheckContract.sol";
import "./Initializable.sol";

contract PriceFeed is Ownable, CheckContract, Initializable, IPriceFeed {
	using SafeMath for uint256;

	string public constant NAME = "PriceFeed";

	bool public isInitialized;

	address public adminContract;

	mapping(address => RegisteredOracle) public registeredOracles;

	modifier isController() {
		require(msg.sender == owner() || msg.sender == adminContract, "Invalid Permission");
		_;
	}

	function setAddresses(address _adminContract) external initializer onlyOwner {
		require(!isInitialized, "Already initialized");
		checkContract(_adminContract);
		isInitialized = true;
		adminContract = _adminContract;
	}

	function setAdminContract(address _admin) external onlyOwner {
		require(_admin != address(0), "Admin address is zero");
		checkContract(_admin);
		adminContract = _admin;
	}

	function addOracle(
		address _token,
		address _oracle
	) external override isController {
		checkContract(_token);
		checkContract(_oracle);
		registeredOracles[_token].oracle = _oracle;
		registeredOracles[_token].isRegistered = true;
		emit RegisteredNewOracle(_token, _oracle);
	}

	function fetchPrice(address _asset) external override returns (uint256) {
		RegisteredOracle memory oracleDetails = registeredOracles[_asset];
		require(oracleDetails.isRegistered, "Asset is not registered!");
		return IOracle(oracleDetails.oracle).fetchPrice();
	}

	function getDirectPrice(address _asset) external view override returns (uint256) {
		RegisteredOracle memory oracleDetails = registeredOracles[_asset];
		require(oracleDetails.isRegistered, "Asset is not registered!");
		return IOracle(oracleDetails.oracle).getDirectPrice();
	}

}

