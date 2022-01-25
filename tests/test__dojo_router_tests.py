from scripts.helper import get_account, get_account2
from scripts.deploy import approve_erc20
from brownie import network, DegenDojo, DojoHouse, DojoRouter, config
import pytest
import time
from web3 import Web3

ENTER_AMOUNT = Web3.toWei(10 ** 4, "ether")
LIQUIDITY_AMOUNT = Web3.toWei(30, "ether")
LARGE_TRADE = Web3.toWei(0.7, "ether")
SMALL_TRADE = Web3.toWei(0.2, "ether")
SLIPPAGE = 5
FAILSLIPPAGE = -50
LINK_AMOUNT = Web3.toWei(30, "ether")


def test_trade_tokens_for_eth():

    account = get_account()
    LINK = config["networks"][network.show_active()]["link_token"]
    WETH = config["networks"][network.show_active()]["weth"]
    dojo_house = DojoHouse[-1]
    dojo_router = DojoRouter[-1]
    dojo_token = DegenDojo[-1]

    account2 = get_account2()
    dojo_token.initiateTrade(1, {"from": account2, "value": LARGE_TRADE})
    # Wait for VRF
    time.sleep(180)
    tx = dojo_token.claimTrade({"from": account2})

    tx = dojo_token.claimTrade({"from": account})
    # make sure enough liquidity in house
    if dojo_house.balance() < LIQUIDITY_AMOUNT:
        tx = dojo_house.enter({"from": account, "value": LIQUIDITY_AMOUNT})
        tx.wait(1)
    # Trade LINK tokens for WETH
    # Approve the LINK
    tx1 = approve_erc20(LINK_AMOUNT * 2, dojo_router, LINK, account,)
    tx1.wait(1)
    # Get the min out
    min_out = dojo_router.getAmountOut(LINK_AMOUNT, WETH, LINK) * (100 - SLIPPAGE) / 100
    fail_min_out = (
        dojo_router.getAmountOut(LINK_AMOUNT, WETH, LINK) * (100 - FAILSLIPPAGE) / 100
    )
    deadline = time.time() + 1000
    fail_deadline = time.time() - 1000
    # Check the min out fails if minout not met
    with pytest.raises(Exception):
        dojo_router.swapTokensForETH(
            LINK_AMOUNT, LINK, 1, fail_min_out, deadline, {"from": account}
        )
    # Check the trade fails if deadline not met
    with pytest.raises(Exception):
        dojo_router.swapTokensForETH(
            LINK_AMOUNT, LINK, 1, min_out, fail_deadline, {"from": account}
        )
    # Swap declaring a spin trade white belt
    dojo_router.swapTokensForETH(
        LINK_AMOUNT, LINK, 1, min_out, deadline, {"from": account},
    )
    # Check can not make a regular trade
    with pytest.raises(Exception):
        dojo_token.initiateTrade(1, {"from": account, "value": LARGE_TRADE})
        # Check can not claim the trade
        tx = dojo_token.claimTrade({"from": account})
    # Make trade with account 2
    account2 = get_account2()
    dojo_token.initiateTrade(1, {"from": account2, "value": LARGE_TRADE})
    # Wait for VRF
    time.sleep(180)
    # Claim the trade (straighnt from DegenToken, no need to use router)
    inital_bal = account.balance()
    tx = dojo_token.claimTrade({"from": account})
    tx.wait(1)
    # Check that the balance of BNB has increased to get bacvk half the
    assert account.balance() > inital_bal
    # Claim the trade for account2
    tx = dojo_token.claimTrade({"from": account2})


def test_trade_eth_for_tokens():
    account = get_account()
    WETH = config["networks"][network.show_active()]["weth"]
    dojo_house = DojoHouse[-1]
    dojo_router = DojoRouter[-1]
    dojo_token = DegenDojo[-1]
    inital_bal = dojo_token.balanceOf(account)
    # make sure enough liquidity in house
    if dojo_house.balance() < LIQUIDITY_AMOUNT:
        tx = dojo_house.enter({"from": account, "value": LIQUIDITY_AMOUNT})
        tx.wait(1)
    # first check requirements
    deadline = time.time() + 1000
    fail_deadline = time.time() - 1000
    # min outs to be set to 1 BNB min out values
    min_out = (
        dojo_router.getAmountOut(10 ** 18, dojo_token, WETH) * (100 - SLIPPAGE) / 100
    )
    fail_min_out = (
        dojo_router.getAmountOut(10 ** 18, dojo_token, WETH)
        * (100 - FAILSLIPPAGE)
        / 100
    )
    dojo_router.swapETHforTokens(
        1, dojo_token, {"from": account, "value": LARGE_TRADE},
    )
    # check that we cannot claim trade early
    with pytest.raises(Exception):
        dojo_token.claimTrade({"from": account})
    # check that with caliming token
    with pytest.raises(Exception):
        dojo_router.claimETHTrade(min_out, deadline, {"from": account})
    time.sleep(180)
    # check bad dealline and amount outs
    with pytest.raises(Exception):
        dojo_router.claimETHTrade(fail_min_out, deadline, {"from": account})
    with pytest.raises(Exception):
        dojo_router.claimETHTrade(min_out, fail_deadline, {"from": account})
    # claim the trade
    dojo_router.claimETHTrade(min_out, deadline, {"from": account})
    # check link blaance was increased
    assert dojo_token.balanceOf(account) > inital_bal
