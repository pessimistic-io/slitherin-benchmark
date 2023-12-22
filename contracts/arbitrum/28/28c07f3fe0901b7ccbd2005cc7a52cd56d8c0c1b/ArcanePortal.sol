pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";

interface IArcane {
    function invokeWizard(string memory _name, address _to) external;
}

contract ArcanePortal is Ownable, ReentrancyGuard {
    uint256 public PUBLIC_SUPPLY = 5355;
    uint256 public RESERVED_SUPPLY = 200;
    uint256 public PRICE = 29990000000000000;
    uint256 public mintCounter = 255;
    uint256 public reservedCounter = 0;
    address private vault;
    bool public portalOpened;

    IArcane public ARCANE;

    function claimWizard(string memory _name) external payable nonReentrant {
        require(portalOpened, "The Portal is closed.");
        require(msg.value >= PRICE, "Not enough ETH to summon");
        require(
            mintCounter <= PUBLIC_SUPPLY,
            "All Wizards Have Been Summoned!"
        );

        ARCANE.invokeWizard(_name, msg.sender);
        mintCounter++;
    }

    function claimReservedWizards(
        string[] memory _names,
        address[] memory _owners
    ) external onlyOwner {
        require(_names.length == _owners.length, "Length");
        require(
            _names.length + reservedCounter <= RESERVED_SUPPLY,
            "Not enough left"
        );
        for (uint i = 0; i < _names.length; i++) {
            ARCANE.invokeWizard(_names[i], _owners[i]);
            reservedCounter++;
        }
    }

    function setPrice(uint256 _newPrice) external onlyOwner {
        PRICE = _newPrice;
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    function setOpened(bool _flag) external onlyOwner {
        portalOpened = _flag;
    }

    function setArcane(address _arcane) external onlyOwner {
        ARCANE = IArcane(_arcane);
    }

    function withdraw() external onlyOwner {
        require(vault != address(0), "Vault is set to 0x0");
        require(payable(vault).send(address(this).balance));
    }
}

