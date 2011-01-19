package A::MoarUselessRSLoader;

use Class::C3::Componentised::LoadActions;

AFTER_APPLY { $_[0]->result_source_instance->inject_resultset_components(['+A::MoarUseless']) };

1;
