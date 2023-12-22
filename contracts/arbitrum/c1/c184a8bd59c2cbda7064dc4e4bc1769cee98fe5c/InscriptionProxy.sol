pragma solidity ^0.8.12;
import "./ERC1967Proxy.sol";

contract InscriptionProxy is ERC1967Proxy {
    constructor(address logic, bytes memory data) ERC1967Proxy(logic, data) {
        // solhint-disable-previous-line no-empty-blocks
    }
}
