//SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Base64} from "./Base64.sol";
import {LibString} from "./LibString.sol";
import {ERC20} from "./ERC20.sol";
import {IRewardTracker} from "./IRewardTracker.sol";
import {IVester} from "./IVester.sol";
//import "./AvaxConstants.sol";
//import "./ArbiConstants.sol";

/// @title On-chain renderer
contract Renderer {
    using LibString for string;
    using LibString for uint256;
    using LibString for address;

    struct GMXData {
        uint256 StakedGMXBal;
        uint256 esGMXBal;
        uint256 StakedesGMXBal;
        uint256 esGMXMaxVestGMXBal;
        uint256 esGMXMaxVestGLPBal;
        uint256 GLPBal;
        uint256 MPsBal;
        uint256 PendingWETHBal;
        uint256 PendingesGMXBal;
        uint256 PendingMPsBal;
    }

    address immutable WETH;
    address immutable GMX;
    address immutable EsGMX;
    address immutable bonusGMX;
    address immutable bonusGmxTracker;  //Staked + Bonus GMX (sbGMX)
    address immutable stakedGmxTracker; //Staked GMX (sGMX)
    address immutable stakedGlpTracker; //Fee + Staked GLP (fsGLP)
    address immutable feeGmxTracker;    //Staked + Bonus + Fee GMX (sbfGMX)
    address immutable feeGlpTracker;    //Fee GLP (fGLP)
    address immutable gmxVester;
    address immutable glpVester;

    function getGMXData(address account) internal view returns (GMXData memory ret) {
       ret.StakedGMXBal = IRewardTracker(stakedGmxTracker).depositBalances(account, GMX);
       ret.esGMXBal = ERC20(EsGMX).balanceOf(account);
       ret.StakedesGMXBal = IRewardTracker(stakedGmxTracker).depositBalances(account, EsGMX);
       ret.esGMXMaxVestGMXBal = IVester(gmxVester).getMaxVestableAmount(account);
       ret.esGMXMaxVestGLPBal = IVester(glpVester).getMaxVestableAmount(account);
       ret.GLPBal = ERC20(stakedGlpTracker).balanceOf(account);
       ret.MPsBal = IRewardTracker(feeGmxTracker).depositBalances(account, bonusGMX);
       ret.PendingWETHBal = IRewardTracker(feeGmxTracker).claimable(account);
       ret.PendingesGMXBal = IRewardTracker(stakedGmxTracker).claimable(account) + IRewardTracker(stakedGlpTracker).claimable(account);
       ret.PendingMPsBal = IRewardTracker(bonusGmxTracker).claimable(account);
       return ret;
    }

    constructor() {
        require(block.chainid == 43114 || block.chainid == 42161, "UNKNOWN_CHAINID");
        bool avax = block.chainid == 43114;
        WETH = avax ? 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7 : 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        GMX = avax ? 0x62edc0692BD897D2295872a9FFCac5425011c661 : 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a;
        EsGMX = avax ? 0xFf1489227BbAAC61a9209A08929E4c2a526DdD17 : 0xf42Ae1D54fd613C9bb14810b0588FaAa09a426cA;
        bonusGMX = avax ? 0x8087a341D32D445d9aC8aCc9c14F5781E04A26d2 : 0x35247165119B69A40edD5304969560D0ef486921;
        bonusGmxTracker = avax ? 0x908C4D94D34924765f1eDc22A1DD098397c59dD4 : 0x4d268a7d4C16ceB5a606c173Bd974984343fea13;  //Staked + Bonus GMX (sbGMX)
        stakedGmxTracker = avax ? 0x2bD10f8E93B3669b6d42E74eEedC65dd1B0a1342 : 0x908C4D94D34924765f1eDc22A1DD098397c59dD4; //Staked GMX (sGMX)
        stakedGlpTracker = avax ? 0x9e295B5B976a184B14aD8cd72413aD846C299660 : 0x1aDDD80E6039594eE970E5872D247bf0414C8903; //Fee + Staked GLP (fsGLP)
        feeGmxTracker = avax ? 0x4d268a7d4C16ceB5a606c173Bd974984343fea13 : 0xd2D1162512F927a7e282Ef43a362659E4F2a728F;    //Staked + Bonus + Fee GMX (sbfGMX)
        feeGlpTracker = avax ? 0xd2D1162512F927a7e282Ef43a362659E4F2a728F : 0x4e971a87900b931fF39d1Aad67697F49835400b6;    //Fee GLP (fGLP)
        gmxVester = avax ? 0x472361d3cA5F49c8E633FB50385BfaD1e018b445 : 0x199070DDfd1CFb69173aa2F7e20906F26B363004;
        glpVester = avax ? 0x62331A7Bd1dfB3A7642B7db50B5509E57CA3154A : 0xA75287d2f8b217273E7FCD7E86eF07D33972042E;
    }

    function s(uint256 i) internal pure returns (string memory) {
        i /= 10**17;
        uint256 integer = i / 10;        
        uint256 fractional = i % 10;
        string memory amount = string(abi.encodePacked(integer.toString(), ".", fractional.toString()));
        return amount;
    }

    function t(string memory name, uint256 value) internal pure returns (string memory)
    {
        return string(abi.encodePacked('{"display_type": "number", "trait_type": "', name, '", "value": ', s(value),'}'));
    }

    function abbreviate(string memory addy) internal pure returns (string memory)
    {
        return string(abi.encodePacked(addy.slice(0,6),'...',addy.slice(38,42)));
    }

    function jsonifyTraits(GMXData memory data) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '"attributes": [', 
                t("esGMX", data.StakedesGMXBal + data.esGMXBal + data.PendingesGMXBal), ',',
                t("MPs", data.MPsBal + data.PendingMPsBal), ',',
                t("GMX Vault Capacity", data.esGMXMaxVestGMXBal), ",",
                t("GLP Vault Capacity", data.esGMXMaxVestGLPBal), ",",
                t("GMX", data.StakedGMXBal), ",",
                t("GLP", data.GLPBal),
                ']'
            )
        );
    }

    function tokenURI(
        uint256 tokenId,
        address escrow
    ) external view returns (string memory svgString) {
        GMXData memory data = getGMXData(escrow);
        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(
                    abi.encodePacked(
                        "{" '"name": "GMX Escrow Ownership",',
                        '"description": "A fully on-chain NFT for trading GMX accounts (esGMX and MPs)",'
                        '"image": "data:image/svg+xml;base64,',
                        Base64.encode(bytes(getSVG(tokenId, escrow, data))),
                        '",',
                        jsonifyTraits(data),
                        "}"
                    )
                )
            )
        );
    }

    // construct image
    function getSVG(
        uint256 tokenId,
        address escrow,
        GMXData memory data
    ) internal pure returns (string memory svgString) {
        string memory fullEscrowAddress = string(abi.encodePacked(escrow.toHexString()));
        string memory abbreviatedAddress = abbreviate(fullEscrowAddress);
        uint256 esGMX = data.StakedesGMXBal + data.esGMXBal + data.PendingesGMXBal;
        uint256 MPs = data.MPsBal + data.PendingMPsBal;
        uint256 GMXBalance = data.StakedGMXBal;
        uint256 GLPBalance = data.GLPBal;

        svgString = string(
            abi.encodePacked(
                "<?xml version='1.0' encoding='UTF-8'?>"
                "<svg xmlns:xlink='http://www.w3.org/1999/xlink' xmlns:svg='http://www.w3.org/2000/svg' xmlns='http://www.w3.org/2000/svg' width='100%' height='100%' viewBox='0 0 160 120'>"
                "<style>"
                ".txt { fill: white; white-space: pre; overflow: hidden; font-family: monospace; text-shadow: 1px 1px 1px black, 2px 2px 1px grey;}"
                "</style>" "<defs>"
                "<linearGradient id='a' gradientUnits='userSpaceOnUse' x1='0' x2='0' y1='0' y2='100%' gradientTransform='rotate(240)'>"
                "<stop offset='0'  stop-color='#2b375e'/>"
                "<stop offset='1'  stop-color='#000000'/>"
                "</linearGradient>"
                "<linearGradient id='b' x1='0.536' y1='0.026' x2='0.011' y2='1' gradientUnits='objectBoundingBox'>"
                "<stop offset='0' stop-color='#03d1cf' stop-opacity='0.988'/>"
                "<stop offset='1' stop-color='#4e09f8'/>"
                "</linearGradient>"
                "<clipPath id='cp'>"
                "<rect width='608' height='472'/>"
                "</clipPath>"
                "</defs>"
                "<rect x='0' y='0' fill='url(#a)' rx='2%' ry='2%' width='100%' height='100%'/>"
                "<g id='gmx' clip-path='url(#cp)'>"
                "<g id='logo' transform='translate(80,55) scale(0.125) '>"
                "<rect width='608' height='472' transform='translate(-1.317 16.974)' fill='rgba(255,255,255,0)'/>"
                "<path d='M1070.463,1104.6,798.486,696,525.667,1104.6H905.756L798.486,948.649l-53.212,81.022H688.683l109.8-162.915L957.28,1104.6Z' transform='translate(-494.667 -647.027)' fill='url(#b)'/>"
                "</g>"
                "</g>   <text x='10' y='10' class='txt'>Escrow ", 
                abbreviatedAddress, 
                "</text><text x='10' y='30' class='txt'>esGMX  ",
                s(esGMX),
                "</text><text x='10' y='50' class='txt'>MPs    ",
                s(MPs),
                "</text><text x='10' y='70' class='txt'>GMX    ",
                s(GMXBalance),
                "</text><text x='10' y='90' class='txt'>GLP    ",
                s(GLPBalance),
                "</text><text x='10' y='110' class='txt'>#",
                tokenId.toString(),
               "</text></svg>"
            )
        );
    }
}
