/// SPDX-License-Identifier: UNLICENSED
/// (c) Theori, Inc. 2022
/// All rights reserved

pragma solidity >=0.8.0;

/**
 * @title AnemoiJive
 * @author Theori, Inc.
 * @notice Implementation of the Anemoi hash function and Jive mode of operation
 */
library AnemoiJive {
    uint256 constant beta = 5;
    uint256 constant alpha_inv =
        17510594297471420177797124596205820070838691520332827474958563349260646796493;
    uint256 constant q =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;
    uint256 constant delta =
        8755297148735710088898562298102910035419345760166413737479281674630323398247;

    function CD(uint256 round) internal pure returns (uint256, uint256) {
        if (round == 0)
            return (
                37,
                8755297148735710088898562298102910035419345760166413737479281674630323398284
            );
        if (round == 1)
            return (
                13352247125433170118601974521234241686699252132838635793584252509352796067497,
                5240474505904316858775051800099222288270827863409873986701694203345984265770
            );
        if (round == 2)
            return (
                8959866518978803666083663798535154543742217570455117599799616562379347639707,
                9012679925958717565787111885188464538194947839997341443807348023221726055342
            );
        if (round == 3)
            return (
                3222831896788299315979047232033900743869692917288857580060845801753443388885,
                21855834035835287540286238525800162342051591799629360593177152465113152235615
            );
        if (round == 4)
            return (
                11437915391085696126542499325791687418764799800375359697173212755436799377493,
                11227229470941648605622822052481187204980748641142847464327016901091886692935
            );
        if (round == 5)
            return (
                14725846076402186085242174266911981167870784841637418717042290211288365715997,
                8277823808153992786803029269162651355418392229624501612473854822154276610437
            );
        if (round == 6)
            return (
                3625896738440557179745980526949999799504652863693655156640745358188128872126,
                20904607884889140694334069064199005451741168419308859136555043894134683701950
            );
        if (round == 7)
            return (
                463291105983501380924034618222275689104775247665779333141206049632645736639,
                1902748146936068574869616392736208205391158973416079524055965306829204527070
            );
        if (round == 8)
            return (
                17443852951621246980363565040958781632244400021738903729528591709655537559937,
                14452570815461138929654743535323908350592751448372202277464697056225242868484
            );
        if (round == 9)
            return (
                10761214205488034344706216213805155745482379858424137060372633423069634639664,
                10548134661912479705005015677785100436776982856523954428067830720054853946467
            );
        if (round == 10)
            return (
                1555059412520168878870894914371762771431462665764010129192912372490340449901,
                17068729307795998980462158858164249718900656779672000551618940554342475266265
            );
        if (round == 11)
            return (
                7985258549919592662769781896447490440621354347569971700598437766156081995625,
                16199718037005378969178070485166950928725365516399196926532630556982133691321
            );
        if (round == 12)
            return (
                9570976950823929161626934660575939683401710897903342799921775980893943353035,
                19148564379197615165212957504107910110246052442686857059768087896511716255278
            );
        if (round == 13)
            return (
                17962366505931708682321542383646032762931774796150042922562707170594807376009,
                5497141763311860520411283868772341077137612389285480008601414949457218086902
            );
        if (round == 14)
            return (
                12386136552538719544323156650508108618627836659179619225468319506857645902649,
                18379046272821041930426853913114663808750865563081998867954732461233335541378
            );
        if (round == 15)
            return (
                21184636178578575123799189548464293431630680704815247777768147599366857217074,
                7696001730141875853127759241422464241772355903155684178131833937483164915734
            );
        if (round == 16)
            return (
                3021529450787050964585040537124323203563336821758666690160233275817988779052,
                963844642109550260189938374814031216012862679737123536423540607519656220143
            );
        if (round == 17)
            return (
                7005374570978576078843482270548485551486006385990713926354381743200520456088,
                12412434690468911461310698766576920805270445399824272791985598210955534611003
            );
        if (round == 18)
            return (
                3870834761329466217812893622834770840278912371521351591476987639109753753261,
                6971318955459107915662273112161635903624047034354567202210253298398705502050
            );
        revert();
    }

    function expmod(
        uint256 base,
        uint256 e,
        uint256 m
    ) internal view returns (uint256 o) {
        assembly {
            // define pointer
            let p := mload(0x40)
            // store data assembly-favouring ways
            mstore(p, 0x20) // Length of Base
            mstore(add(p, 0x20), 0x20) // Length of Exponent
            mstore(add(p, 0x40), 0x20) // Length of Modulus
            mstore(add(p, 0x60), base) // Base
            mstore(add(p, 0x80), e) // Exponent
            mstore(add(p, 0xa0), m) // Modulus
            if iszero(staticcall(sub(gas(), 2000), 0x05, p, 0xc0, p, 0x20)) {
                revert(0, 0)
            }
            // data
            o := mload(p)
        }
    }

    function sbox(uint256 x, uint256 y) internal view returns (uint256, uint256) {
        x = addmod(x, q - mulmod(beta, mulmod(y, y, q), q), q);
        y = addmod(y, q - expmod(x, alpha_inv, q), q);
        x = addmod(addmod(x, mulmod(beta, mulmod(y, y, q), q), q), delta, q);
        return (x, y);
    }

    function ll(uint256 x, uint256 y) internal pure returns (uint256 r0, uint256 r1) {
        r0 = addmod(x, mulmod(5, y, q), q);
        r1 = addmod(y, mulmod(5, r0, q), q);
    }

    function compress(uint256 x, uint256 y) internal view returns (uint256) {
        uint256 sum = addmod(x, y, q);
        uint256 c;
        uint256 d;
        for (uint256 r = 0; r < 19; r++) {
            (c, d) = CD(r);
            x = addmod(x, c, q);
            y = addmod(y, d, q);
            (x, y) = ll(x, y);
            (x, y) = sbox(x, y);
        }
        (x, y) = ll(x, y);
        return addmod(addmod(x, y, q), sum, q);
    }
}

