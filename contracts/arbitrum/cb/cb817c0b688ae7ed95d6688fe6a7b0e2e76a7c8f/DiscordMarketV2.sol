// SPDX-License-Identifier: MPL-2.0
pragma solidity 0.8.11;

import {PausableUpgradeable} from "./PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "./AccessControlUpgradeable.sol";
import {IMarketBehavior} from "./IMarketBehavior.sol";
import {IMarket} from "./IMarket.sol";

contract DiscordMarketV2 is
	IMarketBehavior,
	PausableUpgradeable,
	AccessControlUpgradeable
{
	address public override associatedMarket;
	address public associatedMarketSetter;
	mapping(address => string) private repositories;
	mapping(bytes32 => address) private metrics;
	mapping(bytes32 => address) private properties;
	mapping(bytes32 => bool) private pendingAuthentication;

	// ROLE
	bytes32 public constant KHAOS_ROLE = keccak256("KHAOS_ROLE");

	// event
	event Registered(address _metrics, string _repository);
	event Authenticated(string _repository, uint256 _status, string message);
	event Query(string discordGuild, string publicSignature, address account);

	function initialize() external initializer {
		__AccessControl_init();
		__Pausable_init();
		_setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
		_setRoleAdmin(KHAOS_ROLE, DEFAULT_ADMIN_ROLE);
		_setupRole(KHAOS_ROLE, _msgSender());
	}

	/*
    _discordGuild: ex)
                        Discord guild id: 80351110224678912
    _publicSignature: signature string(created by Khaos)
    */
	function authenticate(
		address _prop,
		string[] memory _args,
		address account
	) external override whenNotPaused returns (bool) {
		require(msg.sender == associatedMarket, "invalid sender");
		require(_args.length == 2, "args error");
		string memory discordGuild = _args[0];
		string memory publicSignature = _args[1];
		bytes32 key = createKey(discordGuild);
		emit Query(discordGuild, publicSignature, account);
		properties[key] = _prop;
		pendingAuthentication[key] = true;
		return true;
	}

	function khaosCallback(
		string memory _discordGuild,
		uint256 _status,
		string memory _message
	) external whenNotPaused {
		require(
			hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
				hasRole(KHAOS_ROLE, msg.sender),
			"illegal access"
		);
		require(_status == 0, _message);
		bytes32 key = createKey(_discordGuild);
		require(pendingAuthentication[key], "not while pending");
		emit Authenticated(_discordGuild, _status, _message);
		register(key, _discordGuild, properties[key]);
	}

	function register(
		bytes32 _key,
		string memory _repository,
		address _property
	) private {
		address _metrics = IMarket(associatedMarket).authenticatedCallback(
			_property,
			_key
		);
		repositories[_metrics] = _repository;
		metrics[_key] = _metrics;
		emit Registered(_metrics, _repository);
	}

	function createKey(string memory _repository)
		private
		pure
		returns (bytes32)
	{
		return keccak256(abi.encodePacked(_repository));
	}

	function getId(address _metrics)
		external
		view
		override
		returns (string memory)
	{
		return repositories[_metrics];
	}

	function getMetrics(string memory _repository)
		external
		view
		override
		returns (address)
	{
		return metrics[createKey(_repository)];
	}

	function addKhaosRole(address _khaos)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		_setupRole(KHAOS_ROLE, _khaos);
	}

	function deleteKhaosRole(address _khaos)
		external
		onlyRole(DEFAULT_ADMIN_ROLE)
	{
		revokeRole(KHAOS_ROLE, _khaos);
	}

	function setAssociatedMarket(address _associatedMarket) external override {
		if (associatedMarket == address(0)) {
			associatedMarket = _associatedMarket;
			associatedMarketSetter = msg.sender;
			return;
		}
		if (associatedMarketSetter == msg.sender) {
			associatedMarket = _associatedMarket;
			return;
		}
		revert("illegal access");
	}

	function name() external pure override returns (string memory) {
		return "Discord";
	}

	function schema() external pure override returns (string memory) {
		return
			// solhint-disable-next-line quotes
			'["Discord Guild (e.g, 80351110224678912)", "Khaos Public Signature"]';
	}

	function pause() external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
		_pause();
	}

	function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) whenPaused {
		_unpause();
	}
}

