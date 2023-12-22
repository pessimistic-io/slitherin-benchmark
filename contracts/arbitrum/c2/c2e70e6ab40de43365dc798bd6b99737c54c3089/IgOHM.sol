pragma solidity >=0.7.5;

import {IERC20MetadataUpgradeable as IERC20} from "./IERC20MetadataUpgradeable.sol";

interface IgOHM is IERC20 {
    function index() external view returns (uint256);
}

