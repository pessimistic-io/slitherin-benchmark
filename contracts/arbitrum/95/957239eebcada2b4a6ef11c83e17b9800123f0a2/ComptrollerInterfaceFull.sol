pragma solidity ^0.5.16;

import "./ComptrollerInterface.sol";
import "./ComptrollerStorage.sol";

contract ComptrollerInterfaceFull is ComptrollerInterface, ComptrollerV7Storage {
    function isDeprecated(CToken cToken) public view returns (bool);
    function getAssetsIn(address account) external view returns (CToken[] memory);
}

