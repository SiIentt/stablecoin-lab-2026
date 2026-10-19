# STUDENT-QUESTIONS.md — Discussion questions (submit with your repo)

Answer directly under each question. 150–300 words each — **reasoning over length**.

---

## A. Permission design

**A1.** The vault holds `MINTER_ROLE`, so it can `burn` any user's balance. Explain why that is a risk, then write out how you would change `Vault` and `SimpleStablecoin` to remove it.

> Your answer: 
>
> The vault holds `MINTER_ROLE`, which allows it to mint tokens and burn tokens from any user’s account. This creates a risk because `SimpleStablecoin.burn` does not check whether the user has approved the burn. The current `Vault.redeem` function only burns tokens belonging to the caller, but the stablecoin gives the vault broader permission than this function needs. The last Ex4 test shows this by making a call as the vault and burning Alice’s balance without her approval.
>
> I would keep the vault’s minting permission but remove the function that allows role holders to burn tokens from any account. Instead, `SimpleStablecoin` should provide a `burnFrom` function that checks the user’s allowance. Before redemption, the user would approve the vault to spend a specific amount of sUSD. The vault would then call `burnFrom(msg.sender, amount)` and return the same amount of collateral.
>
> This design makes redemption depend on the user’s approval. Tests should confirm that redemption fails without approval, fails when the amount exceeds the allowance, and succeeds with sufficient approval. The original unrestricted burn function must also be removed.
<br><br><br>

**A2.** In this contract `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` and `PAUSER_ROLE` all go to the same address. How would you split them in production, and who holds each?

> Your answer:
>
> Giving all three roles to one address creates a single point of failure. If that address is compromised, an attacker could change permissions, create unbacked tokens, and pause the system. I would assign the roles to different actors based on their responsibilities.
>
> `DEFAULT_ADMIN_ROLE` should belong to a multisignature wallet controlled by several independent members. Important role changes should also have a time delay. This would reduce the risk of one person making a harmful change and give others time to review it.
>
> `MINTER_ROLE` should belong only to approved vault contracts. These contracts should check collateral requirements before minting. A normal personal wallet should not be able to create stablecoins without depositing collateral.
>
> `PAUSER_ROLE` should belong to a separate emergency multisignature wallet. Its members should be able to respond quickly to an attack, while restarting the system could require wider approval.
>
> However, separating roles is not enough because the administrator can still grant permissions. The system also needs secure key storage, monitoring of role changes, and clear procedures for handling compromised accounts.
<br><br><br>

---

## B. Pausing and redemption

**B1.** `_update` is the single entry point for every balance change, so `pause()` freezes transfers, minting and redemption together. If you wanted "pause transfers but **allow redemption**", how would you change it? Give the approach — full code not required.

> Your answer:
>
> The current contract uses `whenNotPaused` in `_update`, which handles all token balance changes. Transfers, minting, and burning therefore stop when the contract is paused. Since redemption requires burning sUSD, users also lose access to their collateral during a pause.
>
> To allow redemption, I would replace the general pause check with separate checks for different operations. In a normal transfer, both `from` and `to` are nonzero addresses. Minting uses a zero `from` address, while burning uses a zero `to` address. The contract could block normal transfers during a pause but still allow authorized burns. Minting could have a separate pause setting.
>
> The burn operation must still follow the permission rules. Under the design proposed in A1, the user would need to approve the vault before redeeming. The transfer of collateral back to the user must also remain available.
>
> I would add tests showing that transfers fail while approved redemptions succeed during a pause. Unauthorized burns must still fail. A separate emergency restriction on redemption may be needed if the redemption function itself is under attack.
<br><br><br>

**B2.** In 2008, when a money-market fund "broke the buck", redemptions were frozen for days. In 2023 USDC depegged to $0.87 after a reserve bank failed, but redemptions were **not** shut. Compare the two responses — what does closing the redemption channel, or leaving it open, do to a stablecoin?

> Your answer:
>
> Freezing redemption can reduce immediate withdrawals and give a fund more time to sell assets in an orderly way. However, investors lose the ability to recover their money when they need it. This can reduce confidence and increase selling pressure in the secondary market. The Reserve Primary Fund’s problems in 2008 show how investment losses and a shortage of cash can lead to suspended redemptions and a long repayment process.
>
> Keeping redemption available can help a stablecoin return to its target price. If the token trades below one dollar, eligible traders can buy it at a discount and redeem it for one dollar. This creates demand for the token. However, the process only works when reserves are sufficient and redemption is reliable.
>
> The USDC example needs one qualification. During March 2023, redemption was affected by banking hours and processing delays. Circle later reported that it had cleared most of the backlog. Therefore, redemption was not instant and uninterrupted throughout the crisis.
>
> Overall, reliable redemption supports confidence, but it cannot solve a shortage of reserve assets. Both sufficient backing and available cash are necessary.
>
<br><br><br>

---

## C. Depeg analysis

**C1.** Under what conditions does this coin depeg? Distinguish at least two classes of cause, and say how each one shows up in the invariant `totalCollateral() >= totalSupply()`.

> Your answer:
>
> This stablecoin can lose its peg for different reasons. The invariant `totalCollateral() >= totalSupply()` can identify some problems, but it cannot guarantee a stable market price.
>
> The first cause is a shortage of collateral. For example, an attacker with minting permission could create sUSD without depositing mUSDC. The supply would increase while collateral stayed unchanged. The invariant would fail. Collateral theft could produce the same result by reducing the vault’s reserves.
>
> The second cause is an unavailable redemption channel. If redemption is paused or blocked by a contract error, users cannot exchange their tokens for collateral. The invariant may still hold, but users may sell at a discount because they cannot exit through the vault.
>
> A third cause is a fall in the value of the collateral token. The vault might still hold one collateral token for each sUSD, while each collateral token is worth less than one dollar.
>
> Therefore, the system must check more than token quantities. It must also consider collateral value, access to redemption, and whether users can trust the permission system.
<br><br><br>

**C2.** Suppose an attacker bribes their way to `MINTER_ROLE`, mints 1,000,000 sUSD out of nothing and redeems it all. Describe the flow of funds, and name the step that could have stopped them.

> Your answer:
>
> Assume the vault holds at least one million mUSDC before the attack. After obtaining `MINTER_ROLE`, the attacker calls `mint` directly and creates one million sUSD. This call does not go through `Vault.deposit`, so the vault receives no additional collateral. The stablecoin supply rises, and the backing invariant is broken.
>
> The attacker then calls `redeem` with the newly created tokens. The vault checks its collateral balance, burns the attacker’s sUSD, and transfers one million mUSDC to the attacker. These reserves originally backed tokens held by legitimate users. Burning the attacker’s tokens does not remove the shortage because the attacker has also taken collateral from the system.
>
> If the vault holds less than the requested amount, the full redemption fails with `InsufficientCollateral`. However, the attacker may still withdraw available reserves through smaller redemptions.
>
> The attack should be stopped at the permission or minting stage. Only approved contracts that enforce collateral requirements should receive minting authority. Administrative controls and monitoring should prevent unauthorized role grants. Ex3 shows that the access check works before the attacker receives the role, but the role itself provides dangerous authority.
<br><br><br>

---

## D. Toward RWA

**D1.** Right now the collateral is `MockUSDC` and `totalCollateral()` just reads an on-chain balance — simple and reliable. If the collateral were **US Treasuries**, could this invariant still be written that way? What new problems appear?

> Your answer:
>
> If the collateral were US Treasuries, an on-chain token balance alone would not prove that the stablecoin was fully backed. The tokens would represent claims on assets held outside the blockchain. The system would need evidence that the securities exist, belong to the correct entity, and are available to support redemption.
>
> The backing calculation should use the current value of the verified assets, after allowing for relevant obligations and conservative discounts. Treasury prices can change before maturity, so the system should not always treat their face value as the amount available from an immediate sale. Interest payments and changes in holdings would also need to be recorded correctly.
>
> Liquidity is another issue. Selling securities and receiving cash takes time, while stablecoins can trade continuously. A system may hold enough assets overall but still lack cash to meet immediate withdrawals.
>
> I would therefore require independent reserve checks, reliable price information, regular updates, and a cash buffer. The invariant would compare verified reserve value with stablecoin liabilities, while a separate check would assess the ability to meet short-term redemptions.
<br><br><br>

**D2.** If the collateral were **a building**, how would you put it inside this vault? Which off-chain roles or legal structures would you have to introduce?

> Your answer:
>
> A building cannot be placed directly inside a smart contract. The system would need a legal structure that connects the on-chain tokens to rights over the property. For example, a special-purpose vehicle or trust could own the building, while tokens represent clearly defined shares, debt claims, or rights to income.
>
> The legal documents would need to explain who owns the property, whether it already has a mortgage, how rental income is distributed, and what happens after a default. Creating a token with the building’s address would not, by itself, give token holders ownership or the right to sell it.
>
> Several off-chain participants would also be needed. These could include property managers, independent valuers, auditors, and parties responsible for enforcing the agreement. An oracle could report property values, but those values would be estimates rather than continuously available market prices.
>
> Selling a building can take a long time. I would therefore use conservative borrowing limits and clear redemption rules. Smart contracts could manage records and payments, but they could not remove the legal, valuation, and liquidity risks of the property.
<br><br><br>

---

## E. Tests (Tier 1 required — this is Ex4)

Turn the red tests green in `test/exercises/01_LoopTasks.t.sol` to cover the scenarios below, and write your test function names here:

| Scenario | Your test function name |
|---|---|
| Minting by a non-minter reverts | `test_Ex4_Mint_RevertsForNonMinter` |
| Transfers revert while paused | `test_Ex4_Pause_BlocksTransfers` |
| **Redemption** reverts while paused | `test_Ex4_Pause_BlocksRedeem` |
| An attacker cannot burn someone else's balance | `test_Ex4_AttackerCannotBurnOthersBalance` |
| ...but the vault holding `MINTER_ROLE` can | `test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance` |

That last pair is meant to be read together: the guard is written correctly, but the key was handed to the vault. Keep it in mind when you answer A1.

Now write one more scenario you consider **most likely to be attacked**, and say why you picked it:

> Your answer:
>
> I would prioritize a scenario in which an attacker steals the administrator’s private key. In this lab, the administrator can grant roles to other addresses. An attacker with this key could give themselves `MINTER_ROLE`, create unbacked sUSD, and redeem it for collateral deposited by legitimate users. This attack does not require a calculation error in the contract; it takes advantage of the administrator’s authority.
>
> I would test the complete process. First, legitimate users would deposit collateral and receive sUSD. The attacker would initially fail to mint. The test would then simulate a compromised administrator granting the attacker minting permission. After the attacker minted and redeemed tokens, the test would check the attacker’s collateral balance and the remaining shortage in the vault. It would also check that a legitimate user could no longer redeem more collateral than remained.
>
> I chose this scenario because one compromised account could affect the whole system. Possible protections include multisignature administration, time delays for sensitive role changes, restricted minting paths, and monitoring of unusual token creation.