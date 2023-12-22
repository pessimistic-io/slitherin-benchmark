//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;
import "./PayoutVault.sol";
import "./BeaconProxy.sol";
import "./Ownable.sol";

contract ProxyFactory is Ownable {
    mapping(uint32 => address) public proxies;
    address public beacon;
    address public workerAddress;
    uint32 public counter;

    constructor(address _beacon, address _owner, address _workerAddress) {
        beacon = _beacon;
        /// @dev transfering ownership to multisig owner upon init
        _transferOwnership(_owner);
        workerAddress = _workerAddress;
    }

    event WorkerAddressUpdated(address indexed oldAddress, address newAddress);
    event DeployedProxy(
        address indexed proxyAddress,
        address owner,
        address managerAddress,
        address workerAddress,
        address[] paymentTypes
    );

    modifier onlyOwnerAndWorker() {
        if (msg.sender != owner() && msg.sender != workerAddress) {
            revert Unauthorized();
        }
        _;
    }

    /// @notice allowing owner to set worker address
    /// @param _newAddress new worker address
    function setWorkerAddress(address _newAddress) external onlyOwner {
        /// @dev allowing owner to set address(0) in case we want to not allow any worker address to update
        emit WorkerAddressUpdated(workerAddress, _newAddress);
        workerAddress = _newAddress;
    }

    /// @notice deploy proxy for manager
    /// @param _managerAddress address of manager
    /// @param _paymentTypes array of payment types
    function deployProxy(
        bytes4 _selector,
        address _managerAddress,
        address[] calldata _paymentTypes
    ) external onlyOwnerAndWorker {
        BeaconProxy proxy = new BeaconProxy(
            address(beacon),
            abi.encodeWithSelector(
                _selector, /// @dev equivalent to ImpementationContract(address(0)).initialize.selector
                owner(), /// @dev owner
                _managerAddress,
                workerAddress,
                _paymentTypes
            )
        );
        emit DeployedProxy(address(proxy), owner(), _managerAddress, workerAddress, _paymentTypes);

        /// @dev tracking deployed proxies in a mapping
        counter += 1;
        proxies[counter] = address(proxy);
    }
}

