pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./console.sol";

interface IArcane{
    function invokeWizard(string memory _name, address _to) external;
}

contract ArcanePortal is Ownable, ReentrancyGuard { 
    uint256 public MAX_SUPPLY = 5555;
    uint256 public PRICE = 50000000000000000;
    uint256 public mintCounter=251;
    address private vault;
    bool public portalOpened;

    IArcane public ARCANE;

    function claimWizard(string memory _name) external payable nonReentrant {
        require(portalOpened, "The Portal is closed.");
        require(msg.value >= PRICE, "Not enough ETH to summon");
        require(mintCounter <= MAX_SUPPLY, "All Wizards Have Been Summoned!");

       ARCANE.invokeWizard(_name, msg.sender);

        mintCounter++;
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
        console.log("PAYING ",address(this).balance);
        require(payable(vault).send(address(this).balance));
    }
}

