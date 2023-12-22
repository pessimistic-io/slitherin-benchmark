pragma solidity ^0.8.0;

import "./IDeploymentManager.sol";

interface IUmamiAccessControlled {
    function setDeploymentManager(IDeploymentManager manager) external;
}
