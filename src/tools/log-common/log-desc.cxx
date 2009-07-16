/*! \file log-desc.cxx
 *
 * \author John Reppy
 */

/*
 * COPYRIGHT (c) 2009 The Manticore Project (http://manticore.cs.uchicago.edu)
 * All rights reserved.
 */

#include "event-desc.hxx"
#include "log-desc.hxx"
#include <string.h>
#include <stack>
#include <assert.h>

/* additional info about events */
struct EventGrpInfo {
    std::vector<StateGroup *>		*stateGrps;
    std::vector<IntervalGroup *>	*intervalGrps;
    std::vector<DependentGroup *>	*dependentGrps;
};

inline char *CopyString (const char *s)
{
    if (s == 0) return 0;
    return strcpy (new char[strlen(s)+1], s);
}

/***** class Group member functions *****/

Group::Group (const char *desc, GroupKind kind)
{
    this->_desc = CopyString(desc);
    this->_kind = kind;
}

Group::~Group ()
{
    delete this->_desc;
}


/***** class EventGroup member functions *****/

EventGroup::EventGroup (const char *desc, int nEvents, int nGroups)
    : Group (desc, EVENT_GROUP),
	_events(nEvents, (EventDesc *)0),
	_groups(nGroups, (Group *)0)
{
}

EventGroup::~EventGroup ()
{
}

void EventGroup::AddEvent (int i, EventDesc *item)
{
    this->_events.at(i) = item;
}

void EventGroup::AddGroup (int i, Group *item)
{
    this->_groups.at(i) = item;
    item->SetGroup (this);
}


/***** class StateGroup member functions *****/

StateGroup::StateGroup (const char *desc, int nStates, int nTransitions)
    : Group (desc, STATE_GROUP),
	_stateNames(nStates, (const char *)0),
	_transitions(nTransitions, StateTransition()),
	_events()
{
}

StateGroup::~StateGroup ()
{
}

int StateGroup::NextState (int st, EventDesc *evt) const
{
    for (int i = 0;  i < this->_transitions.size();  i++) {
	if (this->_transitions.at(i)._event == evt)
	    return this->_transitions.at(i)._nextState;
    }
    return -1;
}

void StateGroup::AddState (int i, const char *st)
{
    this->_stateNames.at(i) = CopyString(st);
}

void StateGroup::AddTransition (int i, EventDesc *evt, const char *st)
{
  // first map the state name to an index
    int state;
    for (state = 0;  state < this->_stateNames.size();  state++) {
	if (strcmp(this->_stateNames.at(state), st) == 0)
	    break;
    }

  // then add the transition info
    this->_transitions.at(i)._event = evt;
    this->_transitions.at(i)._nextState = state;

  // look for evt in the _events vector
    for (std::vector<EventDesc *>::iterator iter = this->_events.begin();
	iter < this->_events.end();  iter++
    ) {
	if ((*iter)->Id() == evt->Id())
	    return; /* evt is already in the _events vector */
    }

  // if we get here, then evt should be added to the _events vector
    this->_events.push_back(evt);

}

/***** class IntervalGroup member functions *****/

IntervalGroup::IntervalGroup (const char *desc, EventDesc *a, EventDesc *b)
    : Group (desc, INTERVAL_GROUP),
	_start(a), _end(b)
{
}

IntervalGroup::~IntervalGroup ()
{
}


/***** class DependentGroup member functions *****/

DependentGroup::DependentGroup (const char *desc, EventDesc *src, EventDesc *dst)
    : Group (desc, DEPENDENT_GROUP),
	_src(src), _dst(dst)
{
}

DependentGroup::~DependentGroup ()
{
}


/***** class LogFileDesc member functions *****/

LogFileDesc::LogFileDesc (std::vector<EventDesc *> *evts)
{
    this->_root = 0;
    this->_events = evts;
    this->_info = 0;
}

LogFileDesc::~LogFileDesc ()
{
    delete this->_root;
    delete this->_events;
}

EventDesc *LogFileDesc::FindEventByName (const char *name) const
{
    for (int i = 0;  i < this->_events->size();  i++) {
	if (strcmp(name, this->_events->at(i)->Name()) == 0)
	    return this->_events->at(i);
    }
    return 0;
}

std::vector<StateGroup *> *LogFileDesc::StateGroups (EventDesc *ed) const
{
    if (ed->HasAttr (ATTR_STATE))
	return this->_info[ed->Id()]->stateGrps;
    else
	return 0;
}

std::vector<IntervalGroup *> *LogFileDesc::IntervalGroups (EventDesc *ed) const
{
    if (ed->HasAttr (ATTR_INTERVAL))
	return this->_info[ed->Id()]->intervalGrps;
    else
	return 0;
}

std::vector<DependentGroup *> *LogFileDesc::DependentGroups (EventDesc *ed) const
{
    if (ed->HasAttr (ATTR_DEPENDENT))
	return this->_info[ed->Id()]->dependentGrps;
    else
	return 0;
}

/* add a group to a group vector */
template <class T>
static void AddGroup (std::vector<T *> *&v, T *g)
{
    if (v == 0)
	v = new std::vector<T *>(1, g);
    else
	v->push_back(g);
}

void LogFileDesc::_InitEventInfo ()
{
    class Visitor : public LogDescVisitor {
      public:
	Visitor (LogFileDesc *ld, EventGrpInfo **info) : _logFile(ld), _info(info) { }

	void VisitGroup (EventGroup *) { }
	void VisitStateGroup (StateGroup *grp)
	{
	    std::vector<EventDesc *>::iterator iter;
	    std::vector<EventDesc *> evts = grp->Events();
	    for (std::vector<EventDesc *>::iterator iter = evts.begin();  iter < evts.end();  iter++) {
		EventDesc *ed = *iter;
		AddGroup<StateGroup> (this->_info[ed->Id()]->stateGrps, grp);
	    }
	}
	void VisitIntervalGroup (IntervalGroup *grp)
	{
	    int id = grp->Start()->Id();
	    AddGroup<IntervalGroup> (this->_info[id]->intervalGrps, grp);
	    id = grp->End()->Id();
	    AddGroup<IntervalGroup> (this->_info[id]->intervalGrps, grp);
	}
	void VisitDependentGroup (DependentGroup *grp)
	{
	    int id = grp->Src()->Id();
	    AddGroup<DependentGroup> (this->_info[id]->dependentGrps, grp);
	    id = grp->Dst()->Id();
	    AddGroup<DependentGroup> (this->_info[id]->dependentGrps, grp);
	}
      private:
	EventGrpInfo **_info;
	LogFileDesc *_logFile;

    };

    this->_info = new EventGrpInfo*[this->_events->size()];
    for (int i = 0;  i < this->_events->size();  i++) {
	if (this->_events->at(i)->isSimpleEvent())
	    this->_info[i] = 0;
	else {
	    this->_info[i] = new EventGrpInfo;
	    this->_info[i]->stateGrps = 0;
	    this->_info[i]->intervalGrps = 0;
	    this->_info[i]->dependentGrps = 0;
	}
    }

    Visitor v(this, this->_info);
    this->PreOrderWalk (&v);

}

/* visitor walks of the event hierarchy */

struct StkNode {
    EventGroup	*grp;
    int		i;		// child index in the group

    StkNode (EventGroup *g) { this->grp = g; this->i = 0; }

    Group *Next ()
    {
	if (this->i < grp->NumKids())
	    return grp->Kid(this->i++);
	else
	    return 0;
    }

};

typedef std::stack<StkNode> Stack_t;

//! \brief do a pre-order traversal of the event hierarchy, calling the visitor methods at each
//! node.
void LogFileDesc::PreOrderWalk (LogDescVisitor *visitor)
{
    Stack_t stk;

    visitor->VisitGroup (this->_root);
    stk.push (StkNode(this->_root));
    while (! stk.empty()) {
	Group *p = stk.top().Next();
	if (p == 0) {
	    stk.pop();
	}
	else switch (p->Kind()) {
	  case EVENT_GROUP: {
		EventGroup *grp = reinterpret_cast<EventGroup *>(p);
		visitor->VisitGroup (grp);
		stk.push (StkNode(grp));
	    } break;
	  case STATE_GROUP: {
		StateGroup *grp = reinterpret_cast<StateGroup *>(p);
		visitor->VisitStateGroup (grp);
	    } break;
	  case INTERVAL_GROUP: {
		IntervalGroup *grp = reinterpret_cast<IntervalGroup *>(p);
		visitor->VisitIntervalGroup (grp);
	    } break;
	  case DEPENDENT_GROUP: {
		DependentGroup *grp = reinterpret_cast<DependentGroup *>(p);
		visitor->VisitDependentGroup (grp);
	    } break;
	}
    }
}

//! \brief do a post-order traversal of the event hierarchy, calling the visitor methods at each
//! node.
void LogFileDesc::PostOrderWalk (LogDescVisitor *visitor)
{
#ifdef FIXME
    Stack_t stk;

    stk.push (StkNode(this->_root));
    while (! stk.empty()) {
	Group *p = stk.top().Next();
	if (p == 0) {
	    visitor->VisitGroup (stk.top().grp);
	    stk.pop();
	}
	else {
	    EventGroup *grp = dynamic_cast<EventGroup *>(p);
	    if (grp != 0) {
		visitor->VisitGroup (grp);
		stk.push (StkNode(grp));
   	    }
	    else
		visitor->VisitEvent (static_cast<EventDesc *>(p));
	}
    }
#endif
}
