import styled from 'styled-components';

import { messages } from '../../shared/gettext';
import * as Cell from './cell';
import { normalText } from './common-styles';

const StyledHeaderRow = styled(Cell.Row)({
  marginBottom: '20px',
});

const StyledHeaderLabel = styled(Cell.Label)(normalText);

export default function CustomLists() {
  return (
    <StyledHeaderRow>
      <StyledHeaderLabel>
        {messages.pgettext('select-location-view', 'Custom lists')}
      </StyledHeaderLabel>
    </StyledHeaderRow>
  );
}
