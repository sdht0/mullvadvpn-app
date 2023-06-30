package net.mullvad.mullvadvpn.compose.dialog

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.material.Button
import androidx.compose.material.ButtonDefaults
import androidx.compose.material.Text
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.res.dimensionResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import net.mullvad.mullvadvpn.R
import net.mullvad.mullvadvpn.compose.textfield.DnsTextField
import net.mullvad.mullvadvpn.compose.theme.AlphaDisable
import net.mullvad.mullvadvpn.compose.theme.AlphaInactive
import net.mullvad.mullvadvpn.viewmodel.StagedDns

@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun DnsDialog(
    stagedDns: StagedDns,
    isAllowLanEnabled: Boolean,
    onIpAddressChanged: (String) -> Unit,
    onAttemptToSave: () -> Unit,
    onRemove: () -> Unit,
    onDismiss: () -> Unit
) {
    val buttonSize = dimensionResource(id = R.dimen.button_height)
    val mediumPadding = dimensionResource(id = R.dimen.medium_padding)
    val dialogPadding = 20.dp
    val midPadding = 10.dp
    val smallPadding = 5.dp

    val textSmallSize = dimensionResource(id = R.dimen.text_small).value.sp
    val textMediumSize = dimensionResource(id = R.dimen.text_medium_plus).value.sp
    val textBigSize = dimensionResource(id = R.dimen.text_big).value.sp

    val textFieldFocusRequester = FocusRequester()

    Dialog(
        // Fix for https://issuetracker.google.com/issues/221643630
        properties = DialogProperties(usePlatformDefaultWidth = false),
        onDismissRequest = { onDismiss() },
        content = {
            Column(
                Modifier
                    // Related to the fix for https://issuetracker.google.com/issues/221643630
                    .fillMaxWidth(0.8f)
                    .background(color = MaterialTheme.colorScheme.surface)
                    .padding(dialogPadding)
            ) {
                Text(
                    text =
                        if (stagedDns is StagedDns.NewDns) {
                            stringResource(R.string.add_dns_server_dialog_title)
                        } else {
                            stringResource(R.string.update_dns_server_dialog_title)
                        },
                    color = MaterialTheme.colorScheme.onSurface,
                    fontSize = textBigSize
                )

                Box(
                    Modifier.wrapContentSize().clickable { textFieldFocusRequester.requestFocus() }
                ) {
                    DnsTextField(
                        value = stagedDns.item.address,
                        isValidValue = stagedDns.isValid(),
                        onValueChanged = { newMtuValue -> onIpAddressChanged(newMtuValue) },
                        onFocusChanges = {},
                        onSubmit = { onAttemptToSave() },
                        isEnabled = true,
                        placeholderText = stringResource(R.string.custom_dns_hint),
                        modifier =
                            Modifier.padding(top = midPadding)
                                .focusRequester(textFieldFocusRequester)
                    )
                }

                val errorMessage =
                    when {
                        stagedDns.validationResult is
                            StagedDns.ValidationResult.DuplicateAddress -> {
                            stringResource(R.string.duplicate_address_warning)
                        }
                        stagedDns.item.isLocal && isAllowLanEnabled.not() -> {
                            stringResource(id = R.string.confirm_local_dns)
                        }
                        else -> {
                            null
                        }
                    }

                if (errorMessage != null) {
                    Text(
                        text = errorMessage,
                        fontSize = textSmallSize,
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.padding(top = smallPadding)
                    )
                }

                Button(
                    modifier =
                        Modifier.padding(top = mediumPadding)
                            .height(buttonSize)
                            .defaultMinSize(minHeight = buttonSize)
                            .fillMaxWidth(),
                    colors =
                        ButtonDefaults.buttonColors(
                            backgroundColor = MaterialTheme.colorScheme.primary,
                            contentColor = MaterialTheme.colorScheme.onPrimary,
                            disabledContentColor = MaterialTheme.colorScheme.onPrimary.copy(alpha = AlphaInactive),
                            disabledBackgroundColor = MaterialTheme.colorScheme.primary.copy(alpha = AlphaDisable)
                        ),
                    onClick = { onAttemptToSave() },
                    enabled = stagedDns.isValid()
                ) {
                    Text(
                        text = stringResource(id = R.string.submit_button),
                        fontSize = textMediumSize
                    )
                }

                if (stagedDns is StagedDns.EditDns) {
                    Button(
                        modifier =
                            Modifier.padding(top = mediumPadding)
                                .height(buttonSize)
                                .defaultMinSize(minHeight = buttonSize)
                                .fillMaxWidth(),
                        colors =
                            ButtonDefaults.buttonColors(
                                backgroundColor = MaterialTheme.colorScheme.primary,
                                contentColor = MaterialTheme.colorScheme.onPrimary
                            ),
                        onClick = { onRemove() }
                    ) {
                        Text(
                            text = stringResource(id = R.string.remove_button),
                            fontSize = textMediumSize
                        )
                    }
                }

                Button(
                    modifier =
                        Modifier.padding(top = mediumPadding)
                            .height(buttonSize)
                            .defaultMinSize(minHeight = buttonSize)
                            .fillMaxWidth(),
                    colors =
                        ButtonDefaults.buttonColors(
                            backgroundColor = MaterialTheme.colorScheme.primary,
                            contentColor = MaterialTheme.colorScheme.onPrimary
                        ),
                    onClick = { onDismiss() }
                ) {
                    Text(text = stringResource(id = R.string.cancel), fontSize = textMediumSize)
                }
            }
        }
    )
}
