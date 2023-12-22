pragma solidity ^0.5.16;

import "./Ownable.sol";

interface IComptroller {
    function getAllMarkets() external returns (address[] memory);
    function _setMintPaused(address cToken, bool state) external returns (bool);
    function _setBorrowPaused(address cToken, bool state) external returns (bool);
    function _setTransferPaused(bool state) external returns (bool);
    function _setSeizePaused(bool state) external returns (bool);
}
contract PauseGuardian is Ownable {
    IComptroller public Comptroller;

    constructor(IComptroller comptroller) public {
        Comptroller = comptroller;
    }

    mapping (address => bool) public isSigner;

    function addSigner(address newSigner) external onlyOwner {
        isSigner[newSigner] = true;
    }

    function removeSigner(address oldSigner) external onlyOwner {
        isSigner[oldSigner] = false;
    }

    modifier signerOrOwner() {
        require(msg.sender == owner() || isSigner[msg.sender], "Unauthorized");
        _;
    }

    function pauseAll() external signerOrOwner {
        address[] memory markets = Comptroller.getAllMarkets();
        for (uint i = 0; i < markets.length; i++) {
            Comptroller._setMintPaused(markets[i], true);
            Comptroller._setBorrowPaused(markets[i], true);
        }
        Comptroller._setTransferPaused(true);
        Comptroller._setSeizePaused(true);
    }

    function setMintPaused(address cToken) external signerOrOwner {
        Comptroller._setMintPaused(cToken, true);
    }

    function setBorrowPaused(address cToken) external signerOrOwner {
        Comptroller._setBorrowPaused(cToken, true);
    }

    function pauseAllMints() external signerOrOwner {
        address[] memory markets = Comptroller.getAllMarkets();
        for (uint i = 0; i < markets.length; i++) {
            Comptroller._setMintPaused(markets[i], true);
        }
    }

    function pauseAllBorrows() external signerOrOwner {
        address[] memory markets = Comptroller.getAllMarkets();
        for (uint i = 0; i < markets.length; i++) {
            Comptroller._setBorrowPaused(markets[i], true);
        }
    }

    function setTransferPaused() external signerOrOwner {
        Comptroller._setTransferPaused(true);
    }

    function setSeizePaused() external signerOrOwner {
        Comptroller._setSeizePaused(true);
    }

    function setComptroller(IComptroller comptroller) external onlyOwner {
        Comptroller = comptroller;
    }
}
