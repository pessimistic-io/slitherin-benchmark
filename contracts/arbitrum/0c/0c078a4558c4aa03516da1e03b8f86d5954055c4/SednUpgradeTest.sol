// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

import "./Sedn.sol";
import "./SednForwarder.sol";

contract SednUpgradeTest is Sedn {
    uint256 public yoMama;
    mapping(string => uint256) private _fuckYou;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _trustedForwarder) Sedn(_trustedForwarder) {
        _disableInitializers();
    }
    function initialize(
        address _usdcTokenAddressForChain,
        address _registryDeploymentAddressForChain,
        address _trustedVerifyAddress,
        SednForwarder _trustedForwarder
    ) public initializer {
        Sedn.initSedn_unchained(
            _usdcTokenAddressForChain,
            _registryDeploymentAddressForChain,
            _trustedVerifyAddress,
            _trustedForwarder
            );
        yoMama = 0;
    }

    function bridgeWithdraw(
        uint256 amount,
        UserRequest calldata _userRequest,
        address bridgeImpl
    ) external override payable {
        address to = _userRequest.receiverAddress;
        require(_msgSender() != address(0), "bridgeWithdrawal from the zero address");
        require(to != address(0), "bridgeWithdrawal to the zero address");
        this.withdraw(amount, to);
    }

    function increaseYoMama(uint256 amount) public {
        yoMama += amount;
    }

    function addFuckYou(string memory key, uint256 amount) public {
        _fuckYou[key] += amount;
    }

    function viewFuckYou(string memory key) public view returns (uint256) {
        return _fuckYou[key];
    }
}
