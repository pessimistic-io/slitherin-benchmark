//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IERC20Metadata.sol";

contract SpecialSaleExtra is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    struct Badges{
        bool vetted;
        string vettedLink;    
        bool kycPlus;
        string kycPlusLink;  
    }
    mapping(address => Badges) public badges;
    event LogPoolVettedUpdate(address indexed pool, bool vetted, string vettedLink);
    event LogPoolKYCPlusUpdate(address indexed pool, bool kycPlus, string kycPlusLink);

    function initialize(
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
    }

    function updateVettedStatus(address _pool, string memory _vettedLink) external onlyOwner {
        badges[_pool].vetted = !badges[_pool].vetted;
        badges[_pool].vettedLink = _vettedLink;
        emit LogPoolVettedUpdate(_pool, badges[_pool].vetted, _vettedLink);
    }
    function updateKYCPlusStatus(address _pool, string memory _kycPlusLink) external onlyOwner {
        badges[_pool].kycPlus = !badges[_pool].kycPlus;
        badges[_pool].kycPlusLink = _kycPlusLink;
        emit LogPoolKYCPlusUpdate(_pool, badges[_pool].kycPlus, _kycPlusLink);
    }
}
